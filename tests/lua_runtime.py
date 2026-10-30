"""Shared Lua execution support for addon tests.

Uses the system Lua 5.2/5.3/5.4 shared library (available in the build WSL).
"""
import ctypes
import ctypes.util
import os
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LuaRuntimeCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        library = os.environ.get("RPS_LUA_LIBRARY") or next((path for name in ("lua5.4", "lua5.3", "lua5.2")
                        if (path := ctypes.util.find_library(name))), None)
        if not library:
            raise unittest.SkipTest("Lua shared library unavailable; run in build WSL")
        cls.lua = ctypes.CDLL(library)
        cls.lua.luaL_newstate.restype = ctypes.c_void_p
        cls.lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        cls.lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        cls.lua.luaL_loadstring.restype = ctypes.c_int
        cls.lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                     ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        cls.lua.lua_pcallk.restype = ctypes.c_int
        cls.lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        cls.lua.lua_tolstring.restype = ctypes.c_char_p
        cls.lua.lua_close.argtypes = [ctypes.c_void_p]

    def run_lua(self, script):
        script = "package.path=[[" + (ROOT / "Addons/AIO_Client/Dep_Smallfolk/?.lua").as_posix() + ";]]..package.path\n" + script
        state = self.lua.luaL_newstate()
        self.assertTrue(state)
        try:
            self.lua.luaL_openlibs(state)
            status = self.lua.luaL_loadstring(state, script.encode("utf-8"))
            if not status:
                status = self.lua.lua_pcallk(state, 0, 0, 0, 0, None)
            self.assertEqual(status, 0, self.lua.lua_tolstring(state, -1, None))
        finally:
            self.lua.lua_close(state)

