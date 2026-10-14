# Hostnames públicos derivados de DOMAIN_PREFIX (POSIX sh: lo usan los scripts y edge_nginx).
#   DOMAIN_PREFIX=stage -> stage.sistemasrm.com, stagepos.sistemasrm.com, stageweb.aulasv.com...
#   DOMAIN_PREFIX=      -> sistemasrm.com, pos.sistemasrm.com, web.aulasv.com... (producción)
# Subdominios: ${DOMAIN_PREFIX}<sub>.<dominio>; apex: ${DOMAIN_PREFIX}.<dominio>.
_p="${DOMAIN_PREFIX:-}"

export SRM_APEX="${_p:+$_p.}sistemasrm.com"
export SRM_WWW="${_p}www.sistemasrm.com"
export SRM_POS="${_p}pos.sistemasrm.com"
export SRM_POSAPI="${_p}posapi.sistemasrm.com"

export CCA_APEX="${_p:+$_p.}aulasv.com"
export CCA_WWW="${_p}www.aulasv.com"
export CCA_WEB="${_p}web.aulasv.com"
export CCA_CMS="${_p}cms-web.aulasv.com"
export CCA_PORTAL="${_p}portal-padres.aulasv.com"

unset _p
