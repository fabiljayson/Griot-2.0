"""
URL configuration for the Artifacts app.

Routes:
    /artifacts/<slug>/ → artifact_detail view
"""

from django.urls import path

from . import views

app_name = 'artifacts'

urlpatterns = [
    path(
        '<slug:slug>/',
        views.artifact_detail,
        name='detail',
    ),
]
