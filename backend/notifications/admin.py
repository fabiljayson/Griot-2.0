from django import forms
from django.contrib import admin, messages
from django.shortcuts import redirect, render
from django.urls import path

from . import services
from .models import Notification


class BroadcastForm(forms.Form):
    """The "updates" composer: one message, delivered to every reader."""

    title = forms.CharField(
        max_length=120,
        label='Title',
        help_text='Shown as the notification headline.',
    )
    body = forms.CharField(
        required=False,
        label='Message',
        widget=forms.Textarea(attrs={'rows': 4}),
        help_text='Optional detail shown under the title.',
    )

    def clean_title(self):
        title = self.cleaned_data['title'].strip()
        if not title:
            raise forms.ValidationError('A title is required.')
        return title


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    """Read-only view of what each reader was told.

    Messages are not editable: an inbox is a record of what someone was
    actually sent, and rewriting one afterwards makes it a fabrication. Use the
    broadcast form below to send something new instead.
    """

    list_display = (
        'id', 'user', 'kind', 'title', 'story_title', 'is_read', 'created_at',
    )
    list_filter = ('kind', 'is_read', 'created_at')
    search_fields = ('title', 'body', 'story_title', 'story_slug', 'user__username')
    date_hierarchy = 'created_at'
    readonly_fields = (
        'user', 'kind', 'title', 'body', 'story', 'story_title', 'story_slug',
        'dedupe_key', 'is_read', 'read_at', 'created_at',
    )
    actions = ['mark_selected_read', 'mark_selected_unread']

    def has_add_permission(self, request):
        # Adding a row here would mean a single message, attributed to a real
        # reader, that no send ever produced.
        return False

    def has_change_permission(self, request, obj=None):
        return False

    @admin.action(description='Mark selected as read')
    def mark_selected_read(self, request, queryset):
        updated = queryset.update(is_read=True)
        self.message_user(request, f'{updated} marked read.', messages.SUCCESS)

    @admin.action(description='Mark selected as unread')
    def mark_selected_unread(self, request, queryset):
        updated = queryset.update(is_read=False, read_at=None)
        self.message_user(request, f'{updated} marked unread.', messages.SUCCESS)

    def get_urls(self):
        """Add the broadcast composer above the changelist."""
        return [
            path(
                'broadcast/',
                self.admin_site.admin_view(self.broadcast_view),
                name='notifications_broadcast',
            ),
        ] + super().get_urls()

    def broadcast_view(self, request):
        """Send one announcement to every active reader."""
        if request.method == 'POST':
            form = BroadcastForm(request.POST)
            if form.is_valid():
                created = services.announce(
                    form.cleaned_data['title'], form.cleaned_data['body']
                )
                self.message_user(
                    request,
                    f'Announcement delivered to {created} active readers.',
                    messages.SUCCESS,
                )
                return redirect('admin:notifications_notification_changelist')
        else:
            form = BroadcastForm()

        context = {
            **self.admin_site.each_context(request),
            'form': form,
            'title': 'Send an announcement',
            'opts': Notification._meta,
        }
        return render(request, 'admin/notifications/broadcast.html', context)
