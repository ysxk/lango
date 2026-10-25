import uvicorn

from lango.api import create_app

app = create_app()


def main():
    uvicorn.run(
        app, host="127.0.0.1", port=8000, access_log=False, ws_max_size=65536, ws_max_queue=16
    )


if __name__ == "__main__":
    main()
