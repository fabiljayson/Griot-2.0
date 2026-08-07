from django.urls import path

from .views import AuthTokenRefreshView, CustomTokenObtainPairView, RegisterView

app_name = 'users'

urlpatterns = [
    # SimpleJWT token endpoints (Task 2.1).
    path('token/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', AuthTokenRefreshView.as_view(), name='token_refresh'),

    # Registration.
    path('register/', RegisterView.as_view(), name='register'),
]
