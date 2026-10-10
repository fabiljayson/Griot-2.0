from django.urls import path

from .views import (
    DevCheckoutView,
    RevenueCatWebhookView,
    SubscriptionPlansView,
    SubscriptionStatusView,
)

app_name = 'subscriptions'

urlpatterns = [
    # Paywall source of truth for the signed-in reader.
    path('status/', SubscriptionStatusView.as_view(), name='status'),
    # The plan shelf the paywall renders.
    path('plans/', SubscriptionPlansView.as_view(), name='plans'),
    # Development checkout — disabled unless the server opts in.
    path('checkout/', DevCheckoutView.as_view(), name='checkout'),
    # Store sync — RevenueCat posts purchase lifecycle events here.
    path('webhook/', RevenueCatWebhookView.as_view(), name='revenuecat-webhook'),
]