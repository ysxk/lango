import logging
import re


class PrivacyFilter(logging.Filter):
    def filter(self, record):
        if record.name.startswith(
            (
                "mem0",
                "google",
                "httpx",
                "httpcore",
                "urllib3",
                "websockets",
                "qdrant_client",
                "sqlalchemy",
                "posthog",
            )
        ):
            return False
        if record.exc_info:
            record.msg, record.args, record.exc_info, record.exc_text = (
                "Internal operation failed (details suppressed)",
                (),
                None,
                None,
            )
        else:
            record.msg = re.sub(r"\?[^\s\"']+", "?[redacted]", record.getMessage())
            record.args = ()
        return True


def safe_logging():
    privacy = PrivacyFilter()
    logging.getLogger("uvicorn.access").disabled = True
    root = logging.getLogger()
    if not root.handlers:
        logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    for logger in [root, logging.getLogger("uvicorn"), logging.getLogger("uvicorn.error")]:
        for handler in logger.handlers:
            handler.addFilter(privacy)
    for name in (
        "mem0",
        "google",
        "httpx",
        "httpcore",
        "urllib3",
        "websockets",
        "qdrant_client",
        "sqlalchemy",
        "posthog",
    ):
        logger = logging.getLogger(name)
        logger.handlers = [logging.NullHandler()]
        logger.propagate = False
