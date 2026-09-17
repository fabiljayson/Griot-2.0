#!/bin/bash

# Setup script for exposing Django backend to mobile devices via ngrok
# This script starts the Django development server and ngrok tunnel

echo "=== African Teller - Ngrok Setup Script ==="
echo ""

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "❌ ngrok is not installed. Please install it from https://ngrok.com/download"
    exit 1
fi

# Check if Python is available
if ! command -v python &> /dev/null; then
    echo "❌ Python is not installed or not in PATH"
    exit 1
fi

# Check if Django is installed
if ! python -c "import django" &> /dev/null; then
    echo "❌ Django is not installed. Please run: pip install -r backend/requirements.txt"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Function to start Django server
start_django() {
    echo "🚀 Starting Django development server on port 8000..."
    cd backend
    python manage.py runserver 0.0.0.0:8000 &
    DJANGO_PID=$!
    cd ..
    
    # Wait for server to start
    sleep 3
    
    # Check if server is running
    if kill -0 $DJANGO_PID 2>/dev/null; then
        echo "✅ Django server started successfully (PID: $DJANGO_PID)"
        echo "   Local URL: http://localhost:8000"
        echo "   API URL: http://localhost:8000/api/"
    else
        echo "❌ Failed to start Django server"
        exit 1
    fi
}

# Function to start ngrok
start_ngrok() {
    echo ""
    echo "🌐 Starting ngrok tunnel on port 8000..."
    ngrok http 8000 &
    NGROK_PID=$!
    
    # Wait for ngrok to start
    sleep 5
    
    echo ""
    echo "✅ Ngrok tunnel started (PID: $NGROK_PID)"
    echo ""
    echo "📋 Next steps:"
    echo "1. Open http://localhost:4040 in your browser to see ngrok dashboard"
    echo "2. Copy the HTTPS URL (e.g., https://xxxx-xx-xx-xx-xx.ngrok-free.app)"
    echo "3. Update your Flutter app with the ngrok URL:"
    echo "   flutter run --dart-define=NGROK_URL=https://xxxx-xx-xx-xx-xx.ngrok-free.app"
    echo ""
    echo "🔧 Django settings have been updated to allow ngrok traffic"
    echo "🔧 Flutter ApiClient has been updated with ngrok-skip-browser-warning header"
    echo ""
    echo "⚠️  Note: Keep this terminal open while testing"
    echo "   Press Ctrl+C to stop both servers"
    
    # Handle cleanup on exit
    trap 'echo ""; echo "🛑 Stopping servers..."; kill $DJANGO_PID $NGROK_PID 2>/dev/null; exit 0' INT TERM
}

# Main execution
echo "Starting services..."
start_django
start_ngrok

# Keep script running
wait