iscr_source = ['flx.pak']

caml_modules = [
    'src/compiler/flx_core/flx_ast',
    'src/compiler/flx_core/flx_types',
    'src/compiler/flx_core/flx_srcref',
    'src/compiler/flx_core/flx_typing',
    'src/compiler/flx_core/flx_print',
    'src/compiler/flx_core/flx_exceptions',
    'src/compiler/flx_core/flx_typing2',
    'src/compiler/flx_core/flx_mtypes2',
]

caml_include_paths = [
    'src/compiler/ocs',
    'src/compiler/flx_misc',
]

caml_provide_lib = 'src/compiler/flx_core/flx_core'
