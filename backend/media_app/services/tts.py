"""
Mock Text-to-Speech service for development.

In production, this would integrate with a real TTS provider like:
- ElevenLabs
- Amazon Polly
- Google Cloud TTS
- Azure Speech Services
"""
import random
import time
from datetime import datetime, timedelta
from typing import Optional


class MockTTSService:
    """Mock service simulating TTS API."""
    
    # Available voices for demo
    VOICES = {
        'en': [
            {'id': 'en_male_1', 'name': 'English Male', 'gender': 'male'},
            {'id': 'en_female_1', 'name': 'English Female', 'gender': 'female'},
        ],
        'fr': [
            {'id': 'fr_male_1', 'name': 'French Male', 'gender': 'male'},
            {'id': 'fr_female_1', 'name': 'French Female', 'gender': 'female'},
        ],
    }
    
    def __init__(self):
        self._jobs = {}
    
    def submit_narration(
        self,
        text: str,
        language: str = 'en',
        voice_id: Optional[str] = None,
        speed: float = 1.0,
    ) -> dict:
        """
        Submit a text-to-speech narration request.
        
        Args:
            text: Text to convert to speech
            language: Language code
            voice_id: Optional specific voice ID
            speed: Playback speed multiplier
            
        Returns:
            dict with job_id and status
        """
        # Simulate API delay
        time.sleep(0.05)
        
        # Generate mock job ID
        job_id = f"tts_{random.randint(100000, 999999)}"
        
        # Select voice if not specified
        if not voice_id:
            voices = self.VOICES.get(language, self.VOICES['en'])
            voice_id = random.choice(voices)['id']
        
        # Store job data
        self._jobs[job_id] = {
            'id': job_id,
            'status': 'processing',
            'text_length': len(text),
            'language': language,
            'voice_id': voice_id,
            'created_at': datetime.now().isoformat(),
        }
        
        return {
            'id': job_id,
            'status': 'processing',
            'created_at': self._jobs[job_id]['created_at'],
        }
    
    def get_job_status(self, job_id: str) -> dict:
        """
        Get the status of a TTS job.
        
        Args:
            job_id: The job ID to check
            
        Returns:
            dict with job status and details
        """
        if job_id not in self._jobs:
            return {'error': 'Job not found', 'status': 'unknown'}
        
        job = self._jobs[job_id]
        
        # Simulate completion for demo
        if job['status'] == 'processing' and random.random() > 0.3:
            job['status'] = 'completed'
        
        # Generate mock output when completed
        audio_url = ''
        duration = 0
        file_size = 0
        
        if job['status'] == 'completed':
            # Estimate duration based on text length (~150 words per minute)
            word_count = job['text_length'] / 5  # ~5 chars per word
            duration = int((word_count / 150) * 60)  # Convert to seconds
            audio_url = f'https://storage.example.com/audio/{job_id}.mp3'
            file_size = random.randint(500000, 2000000)  # 500KB - 2MB
        
        return {
            'id': job_id,
            'status': job['status'],
            'audio_url': audio_url,
            'duration': duration,
            'file_size': file_size,
            'voice_id': job['voice_id'],
            'language': job['language'],
            'created_at': job['created_at'],
            'completed_at': datetime.now().isoformat() if job['status'] == 'completed' else None,
        }
    
    def list_voices(self, language: Optional[str] = None) -> list:
        """
        List available voices.
        
        Args:
            language: Optional language filter
            
        Returns:
            List of available voices
        """
        if language:
            return self.VOICES.get(language, [])
        
        # Return all voices
        all_voices = []
        for lang, voices in self.VOICES.items():
            for voice in voices:
                all_voices.append({**voice, 'language': lang})
        return all_voices


# Singleton instance
tts_service = MockTTSService()


def get_tts_service() -> MockTTSService:
    """Get the TTS service instance."""
    return tts_service