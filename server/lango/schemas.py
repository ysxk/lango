from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    SecretStr,
    StringConstraints,
    field_validator,
)

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
OpaqueID = Annotated[
    str, StringConstraints(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)


class Login(Strict):
    email: EmailStr = Field(max_length=254)
    password: SecretStr = Field(min_length=10, max_length=128)


class Register(Login):
    display_name: Name
    invite_code: str = Field(min_length=16, max_length=128)


class RefreshBody(Strict):
    refresh_token: str = Field(min_length=20, max_length=128)


class ProfilePatch(Strict):
    display_name: Name | None = None
    native_language: Literal["zh", "en", "es", "ja", "ko", "fr", "de", "pt", "ar", "hi"] | None = (
        None
    )
    target_language: Literal["en"] | None = None
    level: Literal["A1", "A2", "B1", "B2", "C1", "C2"] | None = None
    goal: str | None = Field(default=None, max_length=1000)
    interests: str | None = Field(default=None, max_length=1000)
    voice: Literal["Kore", "Puck", "Charon", "Fenrir", "Aoede"] | None = None
    speech_rate: float | None = Field(default=None, ge=0.7, le=1.3)
    memory_enabled: bool | None = None
    onboarding_completed: bool | None = None

    @field_validator("*", mode="before")
    @classmethod
    def not_null(cls, value):
        if value is None:
            raise ValueError("Fields cannot be null")
        return value


class InviteBody(Strict):
    max_uses: int = Field(default=1, ge=1, le=100)


class Start(Strict):
    type: Literal["session.start"]
    scenario_id: OpaqueID | None = None
    engine: Literal["cascade", "live"] | None = None
    session_id: OpaqueID | None = None
    mode: Literal["ptt", "hands_free", "half_duplex"]


class TextInput(Strict):
    type: Literal["text.input"]
    text: str = Field(min_length=1, max_length=4000)

    @field_validator("text")
    @classmethod
    def nonempty(cls, text):
        if not text.strip():
            raise ValueError("Text cannot be blank")
        return text.strip()


class Cancel(Strict):
    type: Literal["response.cancel"]
    response_id: OpaqueID


class Ack(Strict):
    type: Literal["playback.ack"]
    response_id: OpaqueID
    sequence: int = Field(ge=0, le=511, strict=True)


class Simple(Strict):
    type: Literal["input.commit", "input.cancel", "session.end", "ping"]


PROFILE_FIELDS = (
    "id",
    "email",
    "display_name",
    "native_language",
    "target_language",
    "level",
    "goal",
    "interests",
    "voice",
    "speech_rate",
    "memory_enabled",
    "onboarding_completed",
    "is_admin",
)


def profile(user):
    return {key: getattr(user, key) for key in PROFILE_FIELDS}
