package com.gymapp.android.data.remote

import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST

interface AuthApi {
    @POST("api/v1/auth/register")
    suspend fun register(@Body body: RegisterRequest): RegistrationResultDto

    @POST("api/v1/auth/login")
    suspend fun login(@Body body: LoginRequest): AuthResultDto

    @POST("api/v1/auth/refresh")
    suspend fun refresh(@Body body: RefreshRequest): RefreshEnvelope

    @POST("api/v1/auth/logout")
    suspend fun logout()

    @GET("api/v1/auth/me")
    suspend fun me(): UserEnvelope

    @POST("api/v1/auth/verify-otp")
    suspend fun verifyOtp(@Body body: VerifyOtpRequest): AuthResultDto

    @POST("api/v1/auth/resend-otp")
    suspend fun resendOtp(@Body body: OtpEmailRequest): ResendOtpResultDto

    @POST("api/v1/auth/change-password")
    suspend fun changePassword(@Body body: ChangePasswordRequest)

    @POST("api/v1/auth/password-reset")
    suspend fun requestPasswordReset(@Body body: PasswordResetRequest)

    @POST("api/v1/auth/password-reset/confirm")
    suspend fun confirmPasswordReset(@Body body: PasswordResetConfirmRequest)

    @DELETE("api/v1/auth/account")
    suspend fun deleteAccount(@Body body: DeleteAccountRequest)
}
