from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    """Liveness probe used by the Flutter client and uptime monitors."""
    return Response({
        'status': 'ok',
        'service': 'griot-2.0-backend',
        'version': '0.1.0',
    })
