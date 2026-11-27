package com.gymapp.android.data.remote

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class AccountUser(
    val id: String,
    val email: String,
    val displayName: String?,
    val emailVerified: Boolean,
)

data class AccountRegistration(
    val user: AccountUser,
    val otpSent: Boolean,
    val resendAfterSeconds: Int,
    val expiresInSeconds: Int,
)

data class OtpResendResult(val accepted: Boolean, val resendAfterSeconds: Int)

class AccountService(private val api: ApiClient) {
    private val _currentUser = MutableStateFlow<AccountUser?>(null)
    val currentUser: StateFlow<AccountUser?> = _currentUser.asStateFlow()

    val tokenStore: SecureTokenStore get() = api.tokenStore

    suspend fun restoreSession(): AccountUser? {
        if (api.tokenStore.load() == null) {
            _currentUser.value = null
            return null
        }
        return try {
            val envelope = api.call { api.authApi.me() }
            val user = envelope.user.toDomain()
            _currentUser.value = user
            user
        } catch (error: ApiException) {
            if (error.isUnauthorized) {
                api.tokenStore.clear()
                _currentUser.value = null
            }
            null
        }
    }

    suspend fun register(name: String, email: String, password: String): AccountRegistration {
        val trimmedName = name.trim().takeIf { it.isNotEmpty() }
        val response = api.call {
            api.authApi.register(RegisterRequest(email, password, trimmedName))
        }
        return AccountRegistration(
            user = response.user.toDomain(),
            otpSent = response.otpSent,
            resendAfterSeconds = response.resendAfterSeconds,
            expiresInSeconds = response.expiresInSeconds,
        )
    }

    suspend fun login(email: String, password: String): AccountUser {
        val response = api.call { api.authApi.login(LoginRequest(email, password)) }
        adopt(response)
        return response.user.toDomain()
    }

    suspend fun verifyOtp(email: String, code: String): AccountUser {
        val response = api.call { api.authApi.verifyOtp(VerifyOtpRequest(email, code)) }
        adopt(response)
        return response.user.toDomain()
    }

    suspend fun resendOtp(email: String): OtpResendResult {
        val response = api.call { api.authApi.resendOtp(OtpEmailRequest(email)) }
        return OtpResendResult(response.status == "accepted", response.resendAfterSeconds)
    }

    suspend fun signOut() {
        try {
            api.call { api.authApi.logout() }
        } catch (_: Exception) {
            // Local sign-out must succeed even if the network does not.
        }
        api.tokenStore.clear()
        _currentUser.value = null
    }

    suspend fun requestPasswordReset(email: String) {
        api.call { api.authApi.requestPasswordReset(PasswordResetRequest(email)) }
    }

    suspend fun confirmPasswordReset(token: String, password: String) {
        api.call { api.authApi.confirmPasswordReset(PasswordResetConfirmRequest(token, password)) }
        api.tokenStore.clear()
        _currentUser.value = null
    }

    suspend fun changePassword(current: String, new: String) {
        api.call { api.authApi.changePassword(ChangePasswordRequest(current, new)) }
    }

    suspend fun deleteAccount(password: String) {
        api.call { api.authApi.deleteAccount(DeleteAccountRequest(password)) }
        api.tokenStore.clear()
        _currentUser.value = null
    }

    private suspend fun adopt(response: AuthResultDto) {
        api.tokenStore.save(
            StoredSession(
                userId = response.user.id,
                email = response.user.email,
                accessToken = response.tokens.accessToken,
                refreshToken = response.tokens.refreshToken,
                accessTokenExpiresAt = response.tokens.accessTokenExpiresAt,
                refreshTokenExpiresAt = response.tokens.refreshTokenExpiresAt,
            ),
        )
        _currentUser.value = response.user.toDomain()
    }

    private fun PublicUserDto.toDomain() = AccountUser(
        id = id,
        email = email,
        displayName = displayName,
        emailVerified = emailVerified,
    )
}
