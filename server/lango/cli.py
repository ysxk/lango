import argparse
import getpass
import json

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from lango.config import Settings
from lango.db import User, make_database
from lango.logging import safe_logging
from lango.migrate import check_schema
from lango.schemas import Login, Register
from lango.security import DUMMY_HASH, create_invite, passwords, verify_password


def main():
    parser = argparse.ArgumentParser(prog="lango")
    commands = parser.add_subparsers(dest="command", required=True)
    admin = commands.add_parser(
        "create-admin", help="Create an administrator using a hidden password prompt"
    )
    admin.add_argument("--email", required=True)
    admin.add_argument("--display-name", required=True)
    invite = commands.add_parser(
        "invite", help="Authenticate an administrator and create an invitation"
    )
    invite.add_argument("--email", required=True)
    invite.add_argument("--max-uses", type=int, default=1, choices=range(1, 101), metavar="1..100")
    invite.add_argument("--hours", type=int, default=72, choices=range(1, 721), metavar="1..720")
    args = parser.parse_args()
    safe_logging()
    try:
        settings = Settings()
    except ValidationError:
        parser.exit(2, "Invalid server configuration; check environment settings.\n")
    engine, factory = make_database(settings)
    try:
        check_schema(engine)
        password = getpass.getpass("Password: ")
        try:
            credentials = Login(email=args.email, password=password)
        except ValidationError:
            parser.exit(2, "A valid email and password of 10–128 characters are required.\n")
        with factory.begin() as db:
            if args.command == "create-admin":
                if password != getpass.getpass("Confirm password: "):
                    parser.exit(2, "Passwords do not match.\n")
                try:
                    validated = Register(
                        email=args.email,
                        password=password,
                        display_name=args.display_name,
                        invite_code="bootstrap-not-an-invitation",
                    )
                except ValidationError:
                    parser.exit(2, "Display name must contain 1–80 characters.\n")
                db.add(
                    User(
                        email=str(credentials.email).lower(),
                        display_name=validated.display_name,
                        password_hash=passwords.hash(password),
                        is_admin=True,
                    )
                )
                db.flush()
                print("Administrator created.")
            else:
                user = db.scalar(select(User).where(User.email == str(credentials.email).lower()))
                valid = verify_password(user.password_hash if user else DUMMY_HASH, password)
                if not user or not valid or not user.is_admin:
                    parser.exit(1, "Administrator authentication failed.\n")
                print(json.dumps(create_invite(db, args.max_uses, args.hours)))
    except IntegrityError:
        parser.exit(1, "Account already exists.\n")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
