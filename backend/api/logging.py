"""Structured logging helpers for the Griot 2.0 backend (Phase 10).

Logs are emitted as single-line JSON so they can be shipped to log
aggregators (CloudWatch, Loki, Papertrail, etc.) without parsing.
"""

import json
import logging

# Standard LogRecord attributes that carry no analytic value in the JSON
# payload (the useful ones are surfaced explicitly below). Keeps each line
# compact while preserving any structured ``extra`` kwargs from callers.
_NOISE_KEYS = frozenset({
    'args',
    'asctime',
    'created',
    'exc_info',
    'exc_text',
    'funcName',
    'levelno',
    'lineno',
    'msecs',
    'msg',
    'pathname',
    'process',
    'processName',
    'relativeCreated',
    'stack_info',
    'taskName',
    'thread',
    'threadName',
})


class JsonFormatter(logging.Formatter):
    """Emit each log record as one JSON object on a single line.

    Standard record fields are included, and any structured `extra` kwargs
    provided by the caller (e.g. request metadata) are merged alongside them.
    """

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            'timestamp': self.formatTime(record, self.datefmt),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in payload and not key.startswith('_') and key not in _NOISE_KEYS:
                payload[key] = value
        if record.exc_info:
            payload['exception'] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)
