from django.urls import path

from . import views

app_name = 'griot_ai'

urlpatterns = [
    path('ask/', views.AskGriotView.as_view(), name='ask'),
    path(
        'conversations/<int:pk>/',
        views.GriotConversationDetailView.as_view(),
        name='conversation-detail',
    ),
]
