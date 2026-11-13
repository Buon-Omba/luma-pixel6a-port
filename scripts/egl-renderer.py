#!/usr/bin/env python3
# Stampa GL_RENDERER/VERSION di un contesto GLES surfaceless (EGL_MESA_platform_surfaceless). Solo test.
import ctypes as C
egl = C.CDLL('libEGL.so.1'); gl = C.CDLL('libGLESv2.so.2')
egl.eglGetProcAddress.restype = C.c_void_p
gpd = C.CFUNCTYPE(C.c_void_p, C.c_uint, C.c_void_p, C.c_void_p)(egl.eglGetProcAddress(b'eglGetPlatformDisplayEXT'))
dpy = gpd(0x31DD, None, None)                      # EGL_PLATFORM_SURFACELESS_MESA
egl.eglInitialize.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p]
assert egl.eglInitialize(dpy, None, None), 'eglInitialize'
egl.eglBindAPI(0x30A0)                             # EGL_OPENGL_ES_API
cfg = C.c_void_p(); n = C.c_int()
egl.eglChooseConfig.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_void_p), C.c_int, C.POINTER(C.c_int)]
attrs = (C.c_int * 3)(0x3040, 0x40, 0x3038)        # EGL_RENDERABLE_TYPE = ES3
egl.eglChooseConfig(dpy, attrs, C.byref(cfg), 1, C.byref(n))
egl.eglCreateContext.restype = C.c_void_p
egl.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
ca = (C.c_int * 3)(0x3098, 3, 0x3038)              # EGL_CONTEXT_MAJOR_VERSION 3
ctx = egl.eglCreateContext(dpy, cfg, None, ca)
egl.eglMakeCurrent.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
assert egl.eglMakeCurrent(dpy, None, None, ctx), 'eglMakeCurrent'
gl.glGetString.restype = C.c_char_p
for k, v in (('RENDERER', 0x1F01), ('VERSION', 0x1F02), ('VENDOR', 0x1F00)):
    print(k, gl.glGetString(v).decode())
# --- prova di rendering: FBO 256x256, clear verde, readback
fbo = C.c_uint(); tex = C.c_uint()
gl.glGenFramebuffers(1, C.byref(fbo)); gl.glBindFramebuffer(0x8D40, fbo)
gl.glGenRenderbuffers(1, C.byref(tex)); gl.glBindRenderbuffer(0x8D41, tex)
gl.glRenderbufferStorage(0x8D41, 0x8058, 256, 256)            # GL_RGBA8
gl.glFramebufferRenderbuffer(0x8D40, 0x8CE0, 0x8D41, tex)
gl.glClearColor.argtypes = [C.c_float] * 4
gl.glClearColor(0.0, 1.0, 0.0, 1.0); gl.glClear(0x4000)
buf = (C.c_ubyte * (256 * 256 * 4))()
gl.glReadPixels(0, 0, 256, 256, 0x1908, 0x1401, buf); gl.glFinish()
px = bytes(buf[:4]); ok = all(bytes(buf[i:i+4]) == b'\x00\xff\x00\xff' for i in range(0, len(buf), 4 * 997))
print('readback', px.hex(), 'OK' if ok else 'ERRATO', 'glGetError', hex(gl.glGetError()))
