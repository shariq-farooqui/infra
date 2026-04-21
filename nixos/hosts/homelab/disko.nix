{
  # Two 1 TB Samsung NVMe SSDs in a single btrfs filesystem.
  # - metadata: raid1 across both drives (~sub-GB overhead, free reliability)
  # - data: single (no mirroring, 2 TB usable, drive loss = partial data loss)
  # - compression: zstd level 3 inline
  # - restic to R2 covers recoverable-value data; btrfs is for capacity.
  #
  # /dev/disk/by-id paths are stable across PCIe re-enumeration. Device IDs
  # confirmed against the target from the Hetzner rescue system. The "a"
  # and "b" attr names are arbitrary labels for the disko blocks; they do
  # not correspond to the kernel's /dev/nvme0n1 vs /dev/nvme1n1 naming,
  # which comes from PCIe enumeration and isn't a stable reference.
  #
  # The btrfs mkfs lives on b's disko block, not a's. Disko processes
  # disks in attr-key declaration order, so partitioning a first ensures
  # its pool partition already exists by the time b's btrfs mkfs runs
  # with a's partition as the extra device. Putting the btrfs on a
  # (with b as extra device) inverts that and fails with "No such file"
  # because b hasn't been partitioned yet.
  disko.devices = {
    disk = {
      a = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-00000_S4GJNX0R532212";
        content = {
          type = "gpt";
          partitions = {
            # UEFI System Partition. systemd-boot and kernel images live here.
            ESP = {
              priority = 1;
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                # Keep the ESP readable only by root; the bootloader doesn't
                # need world access.
                mountOptions = [ "umask=0077" ];
              };
            };
            # Plain GPT partition covering the rest of a. No content
            # type here, so disko leaves it as a raw slice. It gets
            # consumed by the btrfs mkfs declared on b.
            pool = {
              size = "100%";
            };
          };
        };
      };
      b = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-00000_S4GJNX0R535805";
        content = {
          type = "gpt";
          partitions = {
            # b's pool partition runs mkfs.btrfs with a's pool
            # partition (referenced by its disko partlabel) as the extra
            # device. Subvolumes are declared here and provide the final
            # mount layout.
            pool = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-L" "homelab"
                  "-d" "single"
                  "-m" "raid1"
                  "-f"
                  "/dev/disk/by-partlabel/disk-a-pool"
                ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd:3" "noatime" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd:3" "noatime" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd:3" "noatime" ];
                  };
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = [ "compress=zstd:3" "noatime" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
