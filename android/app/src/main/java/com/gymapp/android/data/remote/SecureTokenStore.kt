package com.gymapp.android.data.remote

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private val Context.secureDataStore by preferencesDataStore(name = "forma_session")

@Serializable
data class StoredSession(
    val userId: String,
    val email: String,
    val accessToken: String,
    val refreshToken: String,
    val accessTokenExpiresAt: String,
    val refreshTokenExpiresAt: String,
)

@Serializable
data class PendingVerificationState(
    val email: String,
    val resendAvailableAt: Long,
    val codeExpiresAt: Long,
)

/**
 * Tokens are encrypted with an AES-256-GCM key held by the Android Keystore.
 * The DataStore file only ever contains ciphertext.
 */
class SecureTokenStore(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun save(session: StoredSession) {
        context.secureDataStore.edit { prefs ->
            prefs[SESSION] = encrypt(json.encodeToString(StoredSession.serializer(), session))
        }
    }

    suspend fun load(): StoredSession? {
        val raw = context.secureDataStore.data.first()[SESSION] ?: return null
        return runCatching {
            json.decodeFromString(StoredSession.serializer(), decrypt(raw))
        }.getOrElse {
            clear()
            null
        }
    }

    suspend fun accessToken(): String? = load()?.accessToken

    suspend fun refreshToken(): String? = load()?.refreshToken

    suspend fun clear() {
        context.secureDataStore.edit { prefs -> prefs.remove(SESSION) }
    }

    suspend fun savePendingVerification(value: PendingVerificationState?) {
        context.secureDataStore.edit { prefs ->
            if (value == null) {
                prefs.remove(PENDING_EMAIL)
                prefs.remove(PENDING_RESEND_AT)
                prefs.remove(PENDING_EXPIRES_AT)
            } else {
                prefs[PENDING_EMAIL] = value.email
                prefs[PENDING_RESEND_AT] = value.resendAvailableAt.toString()
                prefs[PENDING_EXPIRES_AT] = value.codeExpiresAt.toString()
            }
        }
    }

    suspend fun pendingVerification(): PendingVerificationState? {
        val prefs = context.secureDataStore.data.first()
        val email = prefs[PENDING_EMAIL] ?: return null
        return PendingVerificationState(
            email = email,
            resendAvailableAt = prefs[PENDING_RESEND_AT]?.toLongOrNull() ?: 0L,
            codeExpiresAt = prefs[PENDING_EXPIRES_AT]?.toLongOrNull() ?: 0L,
        )
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val payload = cipher.iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String {
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        val iv = payload.copyOfRange(0, GCM_IV_LENGTH)
        val body = payload.copyOfRange(GCM_IV_LENGTH, payload.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(body), Charsets.UTF_8)
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "forma.session.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_IV_LENGTH = 12
        const val GCM_TAG_BITS = 128

        val SESSION = stringPreferencesKey("encrypted_session")
        val PENDING_EMAIL = stringPreferencesKey("pending_verification_email")
        val PENDING_RESEND_AT = stringPreferencesKey("pending_verification_resend_at")
        val PENDING_EXPIRES_AT = stringPreferencesKey("pending_verification_expires_at")
    }
}
