package com.gymapp.android.data.remote

import android.content.Context
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import okhttp3.Authenticator
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiException(
    val status: Int,
    val code: String,
    override val message: String,
    val fields: List<ApiFieldError> = emptyList(),
) : Exception(message) {
    val isUnauthorized: Boolean get() = status == 401
    val isEmailNotVerified: Boolean get() = code == "email_not_verified"
    val isNetwork: Boolean get() = status == 0
}

val ApiJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = false
}

private class AuthHeaderInterceptor(private val tokenStore: SecureTokenStore) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = runBlocking { tokenStore.accessToken() }
        val request = if (token.isNullOrBlank()) {
            chain.request()
        } else {
            chain.request().newBuilder().header("Authorization", "Bearer $token").build()
        }
        return chain.proceed(request)
    }
}

private class TokenRefreshAuthenticator(
    private val tokenStore: SecureTokenStore,
    private val baseUrl: String,
    private val bareClient: OkHttpClient,
) : Authenticator {
    private val lock = Any()

    override fun authenticate(route: Route?, response: Response): Request? {
        if (response.request.url.encodedPath.endsWith("/auth/refresh")) return null
        if (responseCount(response) >= 2) return null

        synchronized(lock) {
            val session = runBlocking { tokenStore.load() } ?: return null
            val failedToken = response.request.header("Authorization")?.removePrefix("Bearer ")
            if (!failedToken.isNullOrBlank() && failedToken != session.accessToken) {
                return retry(response.request, session.accessToken)
            }
            val refreshed = runBlocking { refresh(session) } ?: return null
            return retry(response.request, refreshed.accessToken)
        }
    }

    private fun retry(request: Request, token: String): Request =
        request.newBuilder().header("Authorization", "Bearer $token").build()

    private fun refresh(session: StoredSession): StoredSession? {
        val body = ApiJson.encodeToString(RefreshRequest.serializer(), RefreshRequest(session.refreshToken))
        val request = Request.Builder()
            .url("$baseUrl/api/v1/auth/refresh")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        return try {
            bareClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    if (response.code == 401) runBlocking { tokenStore.clear() }
                    return null
                }
                val text = response.body?.string() ?: return null
                val envelope = ApiJson.decodeFromString(RefreshEnvelope.serializer(), text)
                val next = session.copy(
                    accessToken = envelope.tokens.accessToken,
                    refreshToken = envelope.tokens.refreshToken,
                    accessTokenExpiresAt = envelope.tokens.accessTokenExpiresAt,
                    refreshTokenExpiresAt = envelope.tokens.refreshTokenExpiresAt,
                )
                runBlocking { tokenStore.save(next) }
                next
            }
        } catch (_: IOException) {
            null
        }
    }

    private fun responseCount(response: Response): Int {
        var count = 1
        var prior = response.priorResponse
        while (prior != null) {
            count += 1
            prior = prior.priorResponse
        }
        return count
    }
}

class ApiClient(context: Context, baseUrl: String) {
    val tokenStore = SecureTokenStore(context)
    private val normalizedBase = if (baseUrl.endsWith("/")) baseUrl else "$baseUrl/"

    private val bareClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val client = bareClient.newBuilder()
        .addInterceptor(AuthHeaderInterceptor(tokenStore))
        .authenticator(TokenRefreshAuthenticator(tokenStore, normalizedBase.trimEnd('/'), bareClient))
        .build()

    val authApi: AuthApi = Retrofit.Builder()
        .baseUrl(normalizedBase)
        .client(client)
        .addConverterFactory(ApiJson.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(AuthApi::class.java)

    suspend fun <T> call(block: suspend () -> T): T = try {
        block()
    } catch (error: HttpException) {
        val raw = runCatching { error.response()?.errorBody()?.string() }.getOrNull()
        val parsed = raw?.let {
            runCatching { ApiJson.decodeFromString(ApiErrorEnvelope.serializer(), it) }.getOrNull()
        }
        throw ApiException(
            status = error.code(),
            code = parsed?.error?.code ?: "http_${error.code()}",
            message = parsed?.error?.message ?: "The server returned an error. Try again.",
            fields = parsed?.error?.fields.orEmpty(),
        )
    } catch (error: IOException) {
        throw ApiException(
            status = 0,
            code = "network_error",
            message = "The server could not be reached. Check your connection and try again.",
        )
    }
}
