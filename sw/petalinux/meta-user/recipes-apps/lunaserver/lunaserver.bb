SUMMARY = "lunaZCU111 transient capture server (RF clocks, RFDC/MTS, trigger readout, TCP)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# sources are copied into files/src by sw/petalinux/setup.sh
SRC_URI = "file://src/ \
           file://lunaserver.init \
           file://lunaserver.service \
           file://lunaserver-start.sh \
          "
S = "${WORKDIR}/src"

DEPENDS = "rfdc libmetal"
RDEPENDS:${PN} = "rfdc libmetal"

inherit update-rc.d systemd

INITSCRIPT_NAME = "lunaserver"
INITSCRIPT_PARAMS = "start 99 S ."
SYSTEMD_SERVICE:${PN} = "lunaserver.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_compile() {
    oe_runmake TARGET_CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" lunaserver
}

do_install() {
    install -D -m 0755 ${S}/lunaserver ${D}${bindir}/lunaserver
    install -D -m 0755 ${WORKDIR}/lunaserver-start.sh ${D}${bindir}/lunaserver-start.sh
    if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
        install -D -m 0755 ${WORKDIR}/lunaserver.init ${D}${sysconfdir}/init.d/lunaserver
    fi
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -D -m 0644 ${WORKDIR}/lunaserver.service ${D}${systemd_system_unitdir}/lunaserver.service
    fi
}

FILES:${PN} += "${bindir}/* ${sysconfdir}/init.d/* ${systemd_system_unitdir}/*"
