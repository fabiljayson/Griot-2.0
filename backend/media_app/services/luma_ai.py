"""
Mock Luma AI Dream Machine service for development.

In production, this would be replaced with actual Luma AI API calls.
"""
import random
import time
from datetime import datetime, timedelta
from typing import Optional


class MockLumaAIService:
    """Mock service simulating Luma AI Dream Machine API."""
    
    def __init__(self):
        self._jobs = {}  # job_id -> status data
    
    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        """
        Submit a video generation request.
        
        Args:
            prompt: Text prompt for video generation
            image_url: Optional reference image URL
            duration: Video duration in seconds (5-30)
            aspect_ratio: Video aspect ratio
            
        Returns:
            dict with job_id and status
        """
        # Simulate API delay
        time.sleep(0.1)
        
        # Generate mock job ID
        job_id = f"luma_{random.randint(100000, 999999)}"
        
        # Store job data
        self._jobs[job_id] = {
            'id': job_id,
            'status': 'pending',
            'prompt': prompt,
            'created_at': datetime.now().isoformat(),
            'estimated_completion': (
                datetime.now() + timedelta(minutes=random.randint(2, 10))
            ).isoformat(),
        }
        
        return {
            'id': job_id,
            'status': 'pending',
            'created_at': self._jobs[job_id]['created_at'],
            'estimated_completion': self._jobs[job_id]['estimated_completion'],
        }
    
    def get_job_status(self, job_id: str) -> dict:
        """
        Get the status of a video generation job.
        
        Args:
            job_id: The job ID to check
            
        Returns:
            dict with job status and details
        """
        if job_id not in self._jobs:
            return {
                'error': 'Job not found',
                'status': 'unknown',
            }
        
        job = self._jobs[job_id]
        
        # Simulate random progress for demonstration
        # In reality, this would poll Luma AI API
        current_status = job['status']
        
        # Randomly advance status for demo purposes
        if current_status == 'pending' and random.random() > 0.7:
            job['status'] = 'processing'
        elif current_status == 'processing' and random.random() > 0.8:
            job['status'] = 'completed'
        
        # Generate mock output URLs when completed
        video_url = ''
        thumbnail_url = ''
        duration = 0
        
        if job['status'] == 'completed':
            video_url = f'https://storage.example.com/videos/{job_id}.mp4'
            thumbnail_url = f'https://storage.example.com/thumbnails/{job_id}.jpg'
            duration = random.randint(5, 15)
        
        return {
            'id': job_id,
            'status': job['status'],
            'video_url': video_url,
            'thumbnail_url': thumbnail_url,
            'duration': duration,
            'created_at': job['created_at'],
            'completed_at': datetime.now().isoformat() if job['status'] == 'completed' else None,
        }
    
    def cancel_job(self, job_id: str) -> dict:
        """
        Cancel a video generation job.
        
        Args:
            job_id: The job ID to cancel
            
        Returns:
            dict with cancellation status
        """
        if job_id not in self._jobs:
            return {'error': 'Job not found'}
        
        self._jobs[job_id]['status'] = 'cancelled'
        
        return {
            'id': job_id,
            'status': 'cancelled',
            'message': 'Job cancelled successfully',
        }
    
    def list_user_jobs(
        self,
        user_id: int,
        status: Optional[str] = None,
        limit: int = 10,
    ) -> list:
        """
        List video generation jobs for a user.
        
        Args:
            user_id: User ID to filter by
            status: Optional status filter
            limit: Maximum number of results
            
        Returns:
            List of job summaries
        """
        # In a real implementation, this would query the database
        # For mock, return empty list
        return []


# Singleton instance for the mock service
luma_ai_service = MockLumaAIService()


def get_luma_service() -> MockLumaAIService:
    """Get the Luma AI service instance."""
    return luma_ai_service