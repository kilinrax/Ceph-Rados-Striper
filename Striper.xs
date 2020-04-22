#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <radosstriper/libradosstriper.h>

#include "const-c.inc"

MODULE = Ceph::Rados::Striper		PACKAGE = Ceph::Rados::Striper

INCLUDE: const-xs.inc

int
create(io)
    rados_ioctx_t *  io
  PREINIT:
    rados_striper_t  striper;
    int              err;
  INIT:
    New( 0, striper, 1, rados_ioctx_t );
  CODE:
    err = rados_striper_create(&io, &striper);
    if (err < 0)
        croak("cannot create rados striper: %s", strerror(-err));
    RETVAL = err;
  OUTPUT:
    RETVAL

int
_write(striper, soid, data, len, off)
    rados_striper_t  striper
    const char *     soid
    SV *             data
    size_t           len
    uint64_t         off
  PREINIT:
    const char *     buf;
    int              err;
  CODE:
    buf = (const char *)SvPV_nolen(data);
    err = rados_striper_write(striper, soid, buf, len, off);
    if (err < 0)
        croak("cannot write striped object '%s': %s", soid, strerror(-err));
    RETVAL = (err == 0) || (err == len);
  OUTPUT:
    RETVAL

int
_append(striper, soid, data, len)
    rados_striper_t  striper
    const char *     soid
    SV *             data
    size_t           len
  PREINIT:
    const char *     buf;
    int              err;
  CODE:
    buf = (const char *)SvPV(data, len);
    err = rados_striper_append(striper, soid, buf, len);
    if (err < 0)
        croak("cannot append to striped object '%s': %s", soid, strerror(-err));
    RETVAL = err == 0;
  OUTPUT:
    RETVAL

void
_stat(striper, soid)
    rados_striper_t  striper
    const char *     soid
  PREINIT:
    size_t           psize;
    time_t           pmtime;
    int              err;
  PPCODE:
    err = rados_striper_stat(striper, soid, &psize, &pmtime);
    if (err < 0)
        croak("cannot stat object '%s': %s", soid, strerror(-err));
    XPUSHs(sv_2mortal(newSVuv(psize)));
    XPUSHs(sv_2mortal(newSVuv(pmtime)));

SV *
_read(striper, soid, len, off = 0)
    rados_striper_t  striper
    const char *     soid
    size_t           len
    uint64_t         off
  PREINIT:
    char *           buf;
    int              retlen;
  INIT:
    Newx(buf, len, char);
  CODE:
    retlen = rados_striper_read(striper, soid, buf, len, off);
    if (retlen < 0)
        croak("cannot read object '%s': %s", soid, strerror(-retlen));
    RETVAL = newSVpv(buf, retlen);
  OUTPUT:
    RETVAL

void
destroy(striper)
    rados_striper_t  striper
  CODE:
    rados_striper_destroy(striper);
