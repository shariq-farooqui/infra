{ lib, modulesPath, ... }:

{
  # Pulls in sensible defaults for hardware that nixos-generate-config would
  # otherwise detect on an existing installation.
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Intel i7-8700 (Coffee Lake).
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  boot.kernelModules = [ "kvm-intel" ];

  # Modules the kernel must load before the real root filesystem is mounted
  # (from the initramfs): NVMe for the root device, ahci in case of a legacy
  # controller on the same board, xhci_pci + usbhid to keep emergency USB
  # input working at boot.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
  ];

  hardware.enableRedistributableFirmware = true;

  nix.settings.max-jobs = lib.mkDefault "auto";
}
