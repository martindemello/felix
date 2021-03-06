import fbuild
import fbuild.db
from fbuild.builders.file import copy, copy_regex
from fbuild.path import Path
from fbuild.record import Record

import buildsystem
from buildsystem.config import config_call

# ------------------------------------------------------------------------------

@fbuild.db.caches
def build_judytables(ctx, tablegen:fbuild.db.SRC, dst) -> fbuild.db.DST:
    """Create the judytable generator executable."""

    # Make sure the directory exists.
    dst.parent.makedirs()

    # We have to run the tablegen from the working directory to get the files
    # generated in the right place.
    ctx.execute(tablegen.abspath(),
        msg1=tablegen.name,
        msg2=dst,
        cwd=dst.parent,
        color='yellow')

    return dst

@fbuild.db.caches
def prepend_macros(ctx, src, macros, dst) -> fbuild.db.DST:
    """Generate a new version of the input file which has the given macros added to the top as #define's"""
    # Make sure the directory exists.
    dst.parent.makedirs()
    src = Path(src)
    dst = Path(dst)
    outfile = open(dst, 'wb')
    try: 
        for macro in macros:
            outfile.write(bytes('#ifndef '+macro+'\n'+
                                '#define '+macro+' 1\n'+
                                '#endif\n', 'ascii'))
        outfile.write(bytes('#include "../JudyCommon/'+src.name+'"', 'ascii'))
        ctx.logger.check(' * generate', '%s as #define %s and #include %s' % (dst, ','.join(macros), src), color='yellow')
    finally: outfile.close()
    return dst
    
    
# ------------------------------------------------------------------------------

def build_runtime(host_phase, target_phase):
    """
    Builds the judy runtime library, and returns the static and shared
    library versions.
    """

    path = Path('src/judy/src')

    # Copy the header into the runtime library.
    buildsystem.copy_to(target_phase.ctx,
        target_phase.ctx.buildroot / 'share/lib/rtl',
        [path / 'Judy.h'])

    types = config_call('fbuild.config.c.c99.types',
        target_phase.platform, target_phase.c.static)

    if types.voidp.size == 8:
        macros = ['JU_64BIT']
    else:
        macros = ['JU_32BIT']

    if 'windows' in target_phase.platform:
        macros.append('BUILD_JUDY') #Apply this to all source files.

    srcs = [copy(target_phase.ctx, p, target_phase.ctx.buildroot / 'share'/p) for p in [
        path / 'JudyCommon/JudyMalloc.c',
        path / 'JudySL/JudySL.c',
        path / 'JudyHS/JudyHS.c'] +
        (path / 'Judy1' / '*.c').glob() +
        (path / 'JudyL' / '*.c').glob()]
    
    # Copy all the common judy sources we need so people can rebuild the RTL without a source distro
    for p in ((path / 'JudyCommon' / '*.c').glob() + 
              (path / 'Judy*' / '*.h').glob()): 
        if p not in ('JudyMalloc.c', 'JudyPrintJP.c'):
            copy(target_phase.ctx, p, target_phase.ctx.buildroot / 'share'/ p)

    includes = [path, 
                path / 'JudyCommon', 
                path / 'JudyL', 
                path / 'Judy1']
    
    static = buildsystem.build_c_static_lib(target_phase, 'host/lib/rtl/judy',
        srcs=srcs,
        macros=macros,
        includes=includes)

    shared = buildsystem.build_c_shared_lib(target_phase, 'host/lib/rtl/judy',
        srcs=srcs,
        macros=macros,
        includes=includes)

    return Record(static=static, shared=shared)

