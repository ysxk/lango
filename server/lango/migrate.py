from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory

from lango.config import Settings
from lango.db import make_database


def migration_config():
    config = Config()
    config.set_main_option("script_location", str(Path(__file__).parent / "migrations"))
    return config


def upgrade(engine):
    config = migration_config()
    with engine.begin() as connection:
        config.attributes["connection"] = connection
        command.upgrade(config, "head")


def check_schema(engine):
    head = ScriptDirectory.from_config(migration_config()).get_current_head()
    with engine.connect() as connection:
        current = MigrationContext.configure(connection).get_current_revision()
    if current != head:
        raise RuntimeError("Database schema is not current; run python -m lango.migrate")


def main():
    from lango.logging import safe_logging

    safe_logging()
    engine, _ = make_database(Settings())
    try:
        upgrade(engine)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
