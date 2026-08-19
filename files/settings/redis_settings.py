import os
from urllib.parse import quote

_redis_host = os.environ.get('REDIS_HOST', 'redis')
_redis_port = os.environ.get('REDIS_PORT', '6379')

# Redis has no authentication unless it is asked for. On a single-host compose
# deployment it is not published and this stays empty; in Kubernetes the chart
# sets requirepass and passes the value here, because a ClusterIP Service is
# reachable by every pod that can route to it -- which is enough to read the
# cache and the task queue, or to FLUSHALL them.
#
# Quoted, because a generated password may contain characters that would
# otherwise end the userinfo section of the URL.
_redis_password = os.environ.get('REDIS_PASSWORD', '')
_redis_auth = f':{quote(_redis_password, safe="")}@' if _redis_password else ''

_redis_url = f'redis://{_redis_auth}{_redis_host}:{_redis_port}'

BROKER_URL = f'{_redis_url}/0'

CACHES = {
    'default': {
        'BACKEND': 'forail.main.cache.AWXRedisCache',
        'LOCATION': f'{_redis_url}/1',
    }
}

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [f'{_redis_url}/0'],
            'capacity': 10000,
            'group_expiry': 157784760,
        },
    }
}
