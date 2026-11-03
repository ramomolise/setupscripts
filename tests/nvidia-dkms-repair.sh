#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/proxmox/repair-nvidia-dkms.sh
source "$script_dir/../scripts/proxmox/repair-nvidia-dkms.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

package_known() {
    [[ $1 == pve-headers-7.0.0-test-pve ]]
}
[[ $(resolve_header_package 7.0.0-test-pve) == pve-headers-7.0.0-test-pve ]] || \
    fail 'Header package fallback resolution changed.'

detect_nvidia_versions() { printf '%s\n' 610.57.04; }
[[ $(select_nvidia_version '') == 610.57.04 ]] || \
    fail 'Single registered NVIDIA version was not selected.'

detect_nvidia_versions() { printf '%s\n' 600.1 610.57.04; }
if (select_nvidia_version '' >/dev/null 2>&1); then
    fail 'Multiple NVIDIA versions were accepted without an explicit selection.'
fi
[[ $(select_nvidia_version 610.57.04) == 610.57.04 ]] || \
    fail 'Explicit NVIDIA version selection failed.'

events=()
apply_changes=false
requested_version=''
running_kernel() { printf '%s\n' 7.0.0-test-pve; }
resolve_header_package() { printf '%s\n' proxmox-headers-7.0.0-test-pve; }
select_nvidia_version() { printf '%s\n' 610.57.04; }
headers_present() { return 1; }
module_available() { return 1; }
dkms_installed_for_kernel() { return 1; }
package_database_clean() { return 0; }
install_header_package() { fail 'Diagnosis mode attempted to install headers.'; }
install_dkms_module() { fail 'Diagnosis mode attempted to rebuild DKMS.'; }
refresh_module_metadata() { fail 'Diagnosis mode attempted to refresh module metadata.'; }

set +e
diagnosis_output=$(run_recovery 2>&1)
diagnosis_status=$?
set -e
[[ $diagnosis_status == 2 ]] || \
    fail "Diagnosis-needed status changed from 2 to $diagnosis_status."
grep -Fq 'Re-run as root with --apply' <<<"$diagnosis_output" || \
    fail 'Diagnosis did not explain how to apply the repair.'

events=()
apply_changes=true
headers_ready=false
module_ready=false
headers_present() { $headers_ready; }
module_available() { $module_ready; }
dkms_installed_for_kernel() { return 1; }
package_database_clean() { return 0; }
install_header_package() {
    events+=("install-header:$1")
    headers_ready=true
}
install_dkms_module() {
    events+=("install-dkms:$1:$2:$3")
    module_ready=true
}
refresh_module_metadata() { events+=("refresh:$1"); }
print_module_details() { events+=("details:$1"); }

run_recovery >/dev/null
actual=$(printf '%s\n' "${events[@]}")
expected=$'install-header:proxmox-headers-7.0.0-test-pve\ninstall-dkms:610.57.04:7.0.0-test-pve:false\nrefresh:7.0.0-test-pve\ndetails:7.0.0-test-pve'
[[ $actual == "$expected" ]] || fail "Unexpected repair sequence:\n$actual"

events=()
apply_changes=true
headers_ready=false
module_ready=false
headers_present() { $headers_ready; }
module_available() { $module_ready; }
dkms_installed_for_kernel() { $module_ready; }
install_header_package() {
    events+=("install-header:$1")
    headers_ready=true
    module_ready=true
}
install_dkms_module() { fail 'DKMS was rebuilt twice after the header post-install hook succeeded.'; }
refresh_module_metadata() { events+=("refresh:$1"); }
print_module_details() { events+=("details:$1"); }

run_recovery >/dev/null
actual=$(printf '%s\n' "${events[@]}")
expected=$'install-header:proxmox-headers-7.0.0-test-pve\nrefresh:7.0.0-test-pve\ndetails:7.0.0-test-pve'
[[ $actual == "$expected" ]] || fail "Unexpected header-hook repair sequence:\n$actual"

events=()
apply_changes=false
module_available() { return 0; }
headers_present() { return 0; }
dkms_installed_for_kernel() { return 0; }
print_module_details() { events+=(details); }
run_recovery >/dev/null
[[ ${events[*]} == details ]] || fail 'Healthy diagnosis performed a mutation.'

printf '%s\n' 'NVIDIA DKMS recovery tests passed.'
