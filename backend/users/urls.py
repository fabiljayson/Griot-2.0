from django.urls import path

from .views import (
    AuthTokenRefreshView,
    CustomTokenObtainPairView,
    LogoutView,
    RegisterView,
)

app_name = 'users'

urlpatterns = [
    # SimpleJWT token endpoints (Task 2.1).
    path('token/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', AuthTokenRefreshView.as_view(), name='token_refresh'),

    # Server-side revocation: blacklist the refresh token, then the client
    # clears local state. Clearing locally alone leaves the token minting
    # access tokens until it expires.
    path('logout/', LogoutView.as_view(), name='logout'),

    # Registration.
    path('register/', RegisterView.as_view(), name='register'),
]
