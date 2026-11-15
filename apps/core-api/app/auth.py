"""Usuarios, roles, permisos y sesiones. Tablas nuevas: roles, users, auth_sessions."""
import hashlib
import hmac
import os
import secrets
import time
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel
from pydantic import Field as PField
from sqlalchemy import JSON, Column, func
from sqlmodel import Field, Session, SQLModel, select

from contacts.db import engine, get_session

SESSION_HOURS = int(os.getenv("AUTH_SESSION_HOURS", "12") or 12)

MODULES = {"inventario": "Inventario", "contactos": "Empleados", "redes": "Redes", "notas": "Notas", "planos": "Planos", "usuarios": "Usuarios y roles"}
ACTIONS = {"ver": "Ver", "editar": "Crear y editar", "eliminar": "Eliminar"}
ALL_PERMS = {f"{m}.{a}" for m in MODULES for a in ACTIONS}
_METHOD_ACTION = {"GET": "ver", "HEAD": "ver", "OPTIONS": "ver", "DELETE": "eliminar"}

DEFAULT_ROLES = [
    ("Administrador", "Acceso total", ["*"]),
    ("Técnico", "Opera inventario, empleados y redes", [
        "inventario.ver", "inventario.editar", "inventario.eliminar",
        "contactos.ver", "contactos.editar", "redes.ver", "redes.editar",
        "notas.ver", "notas.editar", "notas.eliminar",
        "planos.ver", "planos.editar", "planos.eliminar",
    ]),
    ("Consulta", "Solo lectura", ["inventario.ver", "contactos.ver", "redes.ver", "notas.ver", "planos.ver"]),
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _aware(d: datetime) -> datetime:
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


# ------------------------------------------------------------------ modelos
class Role(SQLModel, table=True):
    __tablename__ = "roles"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(unique=True, index=True, max_length=64)
    description: Optional[str] = Field(default=None, max_length=200)
    permissions: List[str] = Field(default_factory=list, sa_column=Column(JSON))
    is_system: bool = Field(default=False)  # el rol Administrador no se edita ni se borra


class User(SQLModel, table=True):
    __tablename__ = "users"
    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(unique=True, index=True, max_length=64)
    full_name: Optional[str] = Field(default=None, max_length=128)
    password_hash: str = Field(max_length=256)
    role_id: int = Field(foreign_key="roles.id", index=True)
    active: bool = Field(default=True)
    must_change_password: bool = Field(default=False)
    created_at: datetime = Field(default_factory=_now)
    last_login: Optional[datetime] = Field(default=None)


class AuthSession(SQLModel, table=True):
    __tablename__ = "auth_sessions"
    id: Optional[int] = Field(default=None, primary_key=True)
    token_hash: str = Field(unique=True, index=True, max_length=64)
    user_id: int = Field(foreign_key="users.id", index=True)
    created_at: datetime = Field(default_factory=_now)
    expires_at: datetime = Field(index=True)


# ------------------------------------------------------------------ seguridad
def hash_password(pw: str) -> str:
    salt = os.urandom(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"scrypt${salt.hex()}${h.hex()}"


def verify_password(pw: str, stored: str) -> bool:
    try:
        _, salt, h = stored.split("$")
        calc = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt), n=2**14, r=8, p=1, dklen=32)
        return hmac.compare_digest(calc.hex(), h)
    except (ValueError, TypeError):
        return False


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _check_password_policy(pw: str) -> None:
    if len(pw or "") < 8:
        raise HTTPException(422, detail="La contraseña debe tener al menos 8 caracteres")


_FAILS: dict[str, list[float]] = {}  # intentos fallidos por usuario (en memoria)


def _locked(key: str) -> bool:
    now = time.time()
    recientes = [t for t in _FAILS.get(key, []) if now - t < 300]
    _FAILS[key] = recientes
    return len(recientes) >= 5


class Auth:
    def __init__(self, user: User, role: Role):
        self.user, self.role = user, role
        self.username = user.username
        self.permissions = set(role.permissions or [])

    def can(self, perm: str) -> bool:
        return "*" in self.permissions or perm in self.permissions


def _auth_from(session: Session, authorization: str | None) -> Auth:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, detail="Inicia sesión para continuar")
    s = session.exec(select(AuthSession).where(AuthSession.token_hash == _hash_token(authorization[7:].strip()))).first()
    if not s or _aware(s.expires_at) < _now():
        raise HTTPException(401, detail="La sesión expiró. Vuelve a iniciar sesión")
    user = session.get(User, s.user_id)
    if not user or not user.active:
        raise HTTPException(401, detail="Usuario inactivo")
    role = session.get(Role, user.role_id)
    if not role:
        raise HTTPException(403, detail="El usuario no tiene un rol válido")
    return Auth(user, role)


def current_auth(authorization: str | None = Header(default=None), session: Session = Depends(get_session)) -> Auth:
    return _auth_from(session, authorization)


def guard(module: str):
    """Dependencia por módulo: GET=ver, DELETE=eliminar, el resto=editar. /health queda público."""
    def dep(request: Request, authorization: str | None = Header(default=None), session: Session = Depends(get_session)):
        if request.url.path.endswith("/health"):
            return None
        auth = _auth_from(session, authorization)
        action = _METHOD_ACTION.get(request.method, "editar")
        if not auth.can(f"{module}.{action}"):
            raise HTTPException(403, detail=f"No tienes permiso para esta acción ({MODULES.get(module, module)}: {ACTIONS[action].lower()})")
        request.state.auth = auth
        return auth
    return dep


def auth_username(request: Request) -> str:
    """Reemplaza a contacts.common.current_user: el historial registra al usuario real."""
    a = getattr(request.state, "auth", None)
    return a.username if a else "admin"


def _me(auth: Auth, token: str | None = None) -> dict:
    out = {
        "id": auth.user.id, "username": auth.user.username, "full_name": auth.user.full_name,
        "role": auth.role.name, "permissions": sorted(auth.permissions),
        "must_change_password": auth.user.must_change_password,
    }
    if token:
        out["token"] = token
    return out


# ------------------------------------------------------------------ sesión propia
auth_router = APIRouter(prefix="/auth", tags=["auth"])


class LoginIn(BaseModel):
    username: str
    password: str


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str


@auth_router.post("/login")
def login(payload: LoginIn, session: Session = Depends(get_session)):
    key = payload.username.strip().lower()
    if _locked(key):
        raise HTTPException(429, detail="Demasiados intentos fallidos. Espera 5 minutos")
    user = session.exec(select(User).where(User.username == key)).first()
    if not (user and user.active and verify_password(payload.password, user.password_hash)):
        _FAILS.setdefault(key, []).append(time.time())
        raise HTTPException(401, detail="Usuario o contraseña incorrectos")
    role = session.get(Role, user.role_id)
    if not role:
        raise HTTPException(403, detail="El usuario no tiene un rol válido")
    _FAILS.pop(key, None)
    for old in session.exec(select(AuthSession).where(AuthSession.user_id == user.id, AuthSession.expires_at < _now())).all():
        session.delete(old)
    token = secrets.token_urlsafe(32)
    session.add(AuthSession(token_hash=_hash_token(token), user_id=user.id, expires_at=_now() + timedelta(hours=SESSION_HOURS)))
    user.last_login = _now()
    session.add(user)
    session.commit()
    return _me(Auth(user, role), token)


@auth_router.post("/logout", status_code=204)
def logout(authorization: str | None = Header(default=None), session: Session = Depends(get_session)):
    if authorization and authorization.lower().startswith("bearer "):
        s = session.exec(select(AuthSession).where(AuthSession.token_hash == _hash_token(authorization[7:].strip()))).first()
        if s:
            session.delete(s)
            session.commit()


@auth_router.get("/me")
def me(auth: Auth = Depends(current_auth)):
    return _me(auth)


@auth_router.post("/change-password", status_code=204)
def change_password(payload: ChangePasswordIn, authorization: str | None = Header(default=None),
                    auth: Auth = Depends(current_auth), session: Session = Depends(get_session)):
    if not verify_password(payload.current_password, auth.user.password_hash):
        raise HTTPException(400, detail="La contraseña actual no es correcta")
    _check_password_policy(payload.new_password)
    auth.user.password_hash = hash_password(payload.new_password)
    auth.user.must_change_password = False
    session.add(auth.user)
    mine = _hash_token(authorization[7:].strip())
    for s in session.exec(select(AuthSession).where(AuthSession.user_id == auth.user.id)).all():
        if s.token_hash != mine:  # cierra las demás sesiones
            session.delete(s)
    session.commit()


# ------------------------------------------------------------------ administración (permiso "usuarios")
admin_router = APIRouter(prefix="/auth", tags=["usuarios"], dependencies=[Depends(guard("usuarios"))])


class RoleIn(BaseModel):
    name: str = PField(min_length=1, max_length=64)
    description: Optional[str] = PField(default=None, max_length=200)
    permissions: List[str] = []


class UserCreate(BaseModel):
    username: str = PField(min_length=3, max_length=64)
    full_name: Optional[str] = PField(default=None, max_length=128)
    password: str
    role_id: int
    active: bool = True


class UserUpdate(BaseModel):
    full_name: Optional[str] = PField(default=None, max_length=128)
    role_id: int
    active: bool = True


class ResetPasswordIn(BaseModel):
    password: str


def _acting(request: Request) -> Auth:
    return request.state.auth


def _role_out(r: Role, users: int) -> dict:
    return {"id": r.id, "name": r.name, "description": r.description, "permissions": r.permissions or [],
            "is_system": r.is_system, "users": users}


def _user_out(u: User, roles: dict[int, Role]) -> dict:
    r = roles.get(u.role_id)
    return {"id": u.id, "username": u.username, "full_name": u.full_name, "role_id": u.role_id,
            "role": r.name if r else None, "active": u.active, "must_change_password": u.must_change_password,
            "last_login": u.last_login.isoformat() if u.last_login else None}


def _clean_perms(perms: List[str]) -> List[str]:
    bad = [p for p in perms if p not in ALL_PERMS]
    if bad:
        raise HTTPException(422, detail=f"Permisos no válidos: {', '.join(bad)}")
    return sorted(set(perms))


def _other_admins(session: Session, exclude_user_id: int) -> int:
    """Usuarios activos con rol de acceso total, sin contar a [exclude_user_id]."""
    roles = {r.id: r for r in session.exec(select(Role)).all()}
    return sum(1 for u in session.exec(select(User).where(User.active == True, User.id != exclude_user_id)).all()  # noqa: E712
               if "*" in (roles[u.role_id].permissions or []))


@admin_router.get("/catalog")
def catalog():
    return {"modules": [{"id": k, "label": v} for k, v in MODULES.items()],
            "actions": [{"id": k, "label": v} for k, v in ACTIONS.items()]}


@admin_router.get("/roles")
def listar_roles(session: Session = Depends(get_session)):
    counts = {rid: n for rid, n in session.exec(select(User.role_id, func.count()).group_by(User.role_id)).all()}
    return [_role_out(r, counts.get(r.id, 0)) for r in session.exec(select(Role).order_by(Role.name)).all()]


@admin_router.post("/roles", status_code=201)
def crear_rol(payload: RoleIn, session: Session = Depends(get_session)):
    name = " ".join(payload.name.split())
    if session.exec(select(Role).where(func.lower(Role.name) == name.lower())).first():
        raise HTTPException(409, detail=f"Ya existe el rol '{name}'")
    r = Role(name=name, description=payload.description, permissions=_clean_perms(payload.permissions))
    session.add(r)
    session.commit()
    session.refresh(r)
    return _role_out(r, 0)


@admin_router.put("/roles/{role_id}")
def actualizar_rol(role_id: int, payload: RoleIn, session: Session = Depends(get_session)):
    r = session.get(Role, role_id)
    if not r:
        raise HTTPException(404, detail="Rol no encontrado")
    if r.is_system:
        raise HTTPException(400, detail="El rol Administrador no se puede modificar")
    name = " ".join(payload.name.split())
    dup = session.exec(select(Role).where(func.lower(Role.name) == name.lower())).first()
    if dup and dup.id != role_id:
        raise HTTPException(409, detail=f"Ya existe el rol '{name}'")
    r.name, r.description, r.permissions = name, payload.description, _clean_perms(payload.permissions)
    session.add(r)
    session.commit()
    session.refresh(r)
    n = session.exec(select(func.count()).select_from(User).where(User.role_id == role_id)).one()
    return _role_out(r, n)


@admin_router.delete("/roles/{role_id}", status_code=204)
def eliminar_rol(role_id: int, session: Session = Depends(get_session)):
    r = session.get(Role, role_id)
    if not r:
        raise HTTPException(404, detail="Rol no encontrado")
    if r.is_system:
        raise HTTPException(400, detail="El rol Administrador no se puede eliminar")
    if session.exec(select(User).where(User.role_id == role_id)).first():
        raise HTTPException(400, detail="Hay usuarios con este rol. Cámbiales el rol primero")
    session.delete(r)
    session.commit()


@admin_router.get("/users")
def listar_usuarios(session: Session = Depends(get_session)):
    roles = {r.id: r for r in session.exec(select(Role)).all()}
    return [_user_out(u, roles) for u in session.exec(select(User).order_by(User.username)).all()]


@admin_router.post("/users", status_code=201)
def crear_usuario(payload: UserCreate, session: Session = Depends(get_session)):
    username = payload.username.strip().lower()
    if " " in username:
        raise HTTPException(422, detail="El usuario no puede tener espacios")
    if session.exec(select(User).where(User.username == username)).first():
        raise HTTPException(409, detail=f"El usuario '{username}' ya existe")
    if not session.get(Role, payload.role_id):
        raise HTTPException(404, detail="Rol no encontrado")
    _check_password_policy(payload.password)
    u = User(username=username, full_name=(payload.full_name or "").strip() or None, role_id=payload.role_id,
             password_hash=hash_password(payload.password), active=payload.active, must_change_password=True)
    session.add(u)
    session.commit()
    session.refresh(u)
    return _user_out(u, {r.id: r for r in session.exec(select(Role)).all()})


@admin_router.put("/users/{user_id}")
def actualizar_usuario(user_id: int, payload: UserUpdate, request: Request, session: Session = Depends(get_session)):
    u = session.get(User, user_id)
    if not u:
        raise HTTPException(404, detail="Usuario no encontrado")
    role = session.get(Role, payload.role_id)
    if not role:
        raise HTTPException(404, detail="Rol no encontrado")
    if u.id == _acting(request).user.id and not payload.active:
        raise HTTPException(400, detail="No puedes desactivarte a ti mismo")
    era_admin = "*" in (session.get(Role, u.role_id).permissions or [])
    sigue_admin = payload.active and "*" in (role.permissions or [])
    if u.active and era_admin and not sigue_admin and _other_admins(session, u.id) == 0:
        raise HTTPException(400, detail="Debe quedar al menos un administrador activo")
    u.full_name = (payload.full_name or "").strip() or None
    u.role_id, u.active = payload.role_id, payload.active
    session.add(u)
    if not payload.active:  # cierra sus sesiones
        for s in session.exec(select(AuthSession).where(AuthSession.user_id == u.id)).all():
            session.delete(s)
    session.commit()
    session.refresh(u)
    return _user_out(u, {r.id: r for r in session.exec(select(Role)).all()})


@admin_router.post("/users/{user_id}/reset-password", status_code=204)
def resetear_clave(user_id: int, payload: ResetPasswordIn, session: Session = Depends(get_session)):
    u = session.get(User, user_id)
    if not u:
        raise HTTPException(404, detail="Usuario no encontrado")
    _check_password_policy(payload.password)
    u.password_hash = hash_password(payload.password)
    u.must_change_password = True
    session.add(u)
    for s in session.exec(select(AuthSession).where(AuthSession.user_id == u.id)).all():
        session.delete(s)
    session.commit()


# ------------------------------------------------------------------ arranque
def init_auth() -> None:
    SQLModel.metadata.create_all(engine)  # solo crea las tablas que no existen
    with Session(engine) as s:
        if not s.exec(select(Role)).first():
            for name, desc, perms in DEFAULT_ROLES:
                s.add(Role(name=name, description=desc, permissions=perms, is_system=(name == "Administrador")))
            s.commit()
        if not s.exec(select(User)).first():
            admin_role = s.exec(select(Role).where(Role.is_system == True)).first()  # noqa: E712
            pw = os.getenv("ADMIN_PASSWORD", "").strip()
            generated = not pw
            if generated:
                pw = secrets.token_urlsafe(12)
                print(f"[auth] Usuario inicial 'admin' con contraseña temporal: {pw}  (se pedirá cambiarla)", flush=True)
            s.add(User(username="admin", full_name="Administrador", password_hash=hash_password(pw),
                       role_id=admin_role.id, must_change_password=generated))
            s.commit()
