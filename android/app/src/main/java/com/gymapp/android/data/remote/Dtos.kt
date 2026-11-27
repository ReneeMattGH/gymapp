package com.gymapp.android.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RegisterRequest(
    val email: String,
    val password: String,
    val displayName: String? = null,
)

@Serializable
data class LoginRequest(val email: String, val password: String)

@Serializable
data class RefreshRequest(@SerialName("refreshToken") val refreshToken: String)

@Serializable
data class OtpEmailRequest(val email: String)

@Serializable
data class VerifyOtpRequest(val email: String, val code: String)

@Serializable
data class PasswordResetRequest(val email: String)

@Serializable
data class PasswordResetConfirmRequest(val token: String, val password: String)

@Serializable
data class ChangePasswordRequest(val currentPassword: String, val newPassword: String)

@Serializable
data class DeleteAccountRequest(val password: String)

@Serializable
data class PublicUserDto(
    val id: String,
    val email: String,
    val displayName: String? = null,
    val emailVerified: Boolean = false,
)

@Serializable
data class AuthTokensDto(
    val accessToken: String,
    val accessTokenExpiresAt: String,
    val refreshToken: String,
    val refreshTokenExpiresAt: String,
)

@Serializable
data class AuthResultDto(val user: PublicUserDto, val tokens: AuthTokensDto)

@Serializable
data class RegistrationResultDto(
    val user: PublicUserDto,
    val otpSent: Boolean,
    val resendAfterSeconds: Int,
    val expiresInSeconds: Int,
)

@Serializable
data class ResendOtpResultDto(
    val status: String,
    val resendAfterSeconds: Int,
)

@Serializable
data class RefreshEnvelope(val tokens: AuthTokensDto)

@Serializable
data class UserEnvelope(val user: PublicUserDto)

@Serializable
data class ApiErrorEnvelope(val error: ApiErrorBody)

@Serializable
data class ApiErrorBody(
    val code: String,
    val message: String,
    val fields: List<ApiFieldError>? = null,
)

@Serializable
data class ApiFieldError(val field: String, val message: String)
