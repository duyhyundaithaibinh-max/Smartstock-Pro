"""Print the one-time SmartStock bootstrap secret to a trusted local terminal.

Run only from the host's trusted administration session. Never paste the output
into logs, tickets, chat, screenshots, or source control.
"""
from app.auth import AuthError, read_bootstrap_secret


def main() -> None:
    try:
        print(read_bootstrap_secret())
    except AuthError as exc:
        raise SystemExit(str(exc)) from exc


if __name__ == "__main__":
    main()
