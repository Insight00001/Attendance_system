"""
config/database.py — SQLAlchemy instance + raw psycopg2 pool
"""
from __future__ import annotations

from typing import Optional
from flask_sqlalchemy import SQLAlchemy
import psycopg2
from psycopg2 import pool as pg_pool
import os


# SQLAlchemy instance (ORM)
db = SQLAlchemy()


class DatabasePool:
    """Thread-safe PostgreSQL connection pool for raw queries."""

    _pool: Optional[pg_pool.ThreadedConnectionPool] = None

    @classmethod
    def get_pool(cls) -> pg_pool.ThreadedConnectionPool:
        if cls._pool is None:
            cls._pool = pg_pool.ThreadedConnectionPool(
                minconn=2,
                maxconn=20,
                dsn=os.getenv("DATABASE_URL"),
            )
        return cls._pool

    @classmethod
    def get_connection(cls):
        return cls.get_pool().getconn()

    @classmethod
    def return_connection(cls, conn):
        cls.get_pool().putconn(conn)

    @classmethod
    def close_all(cls):
        if cls._pool:
            cls._pool.closeall()
            cls._pool = None


class RawDB:
    """
    Context manager for raw psycopg2 queries.
    Usage:
        with RawDB() as (conn, cur):
            cur.execute("SELECT * FROM users WHERE id = %s", (uid,))
            row = cur.fetchone()
    """

    def __init__(self, autocommit: bool = False):
        self.autocommit = autocommit
        self.conn = None
        self.cur = None

    def __enter__(self):
        self.conn = DatabasePool.get_connection()
        self.conn.autocommit = self.autocommit
        self.cur = self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        return self.conn, self.cur

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type:
            self.conn.rollback()
        else:
            if not self.autocommit:
                self.conn.commit()
        self.cur.close()
        DatabasePool.return_connection(self.conn)
        return False  # Re-raise exceptions
