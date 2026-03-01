#!/usr/bin/env bash
set -e

### --- CONFIG --- ###
DISK_INPUT="$1"      # Your VM disk file (qcow2, vmdk, vdi, vhdx, raw)
IMAGE_NAME="zorin-os-18-gce"
BUCKET_NAME="gce-custom-images-yourbucket"
RAW_IMG="disk.raw"
TAR_IMG="disk.tar.gz"
PROJECT_ID="$(gcloud config get-value project)"
ZONE="us-central1-a"

if [ -z "$DISK_INPUT" ]; then
    echo "Usage: ./gce-image-build.sh <disk-image-file>"
    exit 1
fi

echo "[+] Input disk: $DISK_INPUT"
echo "[+] Project: $PROJECT_ID"
echo "[+] Bucket: $BUCKET_NAME"

### --- REQUIREMENTS --- ###
echo "[+] Installing required tools..."
sudo apt-get update -y
sudo apt-get install -y qemu-utils libguestfs-tools cloud-utils

### --- CONVERT INPUT → RAW --- ###
echo "[+] Converting disk to RAW format..."
qemu-img convert -O raw "$DISK_INPUT" "$RAW_IMG"

### --- MOUNT RAW + INSTALL CLOUD PACKAGES --- ###
echo "[+] Installing cloud-init & Google Guest Environment..."

sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 "$RAW_IMG"
sleep 2

MOUNTPOINT=$(mktemp -d)
sudo mount /dev/nbd0p1 "$MOUNTPOINT" || sudo mount /dev/nbd0p2 "$MOUNTPOINT"

sudo mount --bind /dev "$MOUNTPOINT/dev"
sudo mount --bind /proc "$MOUNTPOINT/proc"
sudo mount --bind /sys "$MOUNTPOINT/sys"

cat <<EOF | sudo chroot "$MOUNTPOINT" bash
apt-get update -y

# Install cloud-init
apt-get install -y cloud-init

# Install Google Guest Environment (metadata, networking, shutdown scripts)
apt-get install -y google-compute-engine \
                   google-compute-engine-oslogin \
                   google-guest-agent \
                   google-osconfig-agent || true

# Enable serial console
systemctl enable serial-getty@ttyS0.service || true

# Clean machine-id
truncate -s 0 /etc/machine-id

# Ensure DHCP/virtio networking
apt-get install -y net-tools ifupdown
EOF

sudo umount "$MOUNTPOINT/dev"
sudo umount "$MOUNTPOINT/proc"
sudo umount "$MOUNTPOINT/sys"
sudo umount "$MOUNTPOINT"

sudo qemu-nbd --disconnect /dev/nbd0
sleep 2

### --- PACKAGE RAW FOR GOOGLE CLOUD --- ###
echo "[+] Packaging RAW image into TAR.GZ..."
tar -Sczf "$TAR_IMG" "$RAW_IMG"

### --- UPLOAD TO GCS --- ###
echo "[+] Uploading image to GCS..."
gsutil mb -p "$PROJECT_ID" gs://$BUCKET_NAME/ || true
gsutil cp "$TAR_IMG" gs://$BUCKET_NAME/

### --- CREATE CUSTOM IMAGE IN GCP --- ###
echo "[+] Creating custom GCE image..."
gcloud compute images create "$IMAGE_NAME" \
    --source-uri=gs://$BUCKET_NAME/$TAR_IMG \
    --guest-os-features=VIRTIO_SCSI_MULTIQUEUE \
    --guest-os-features=UEFI_COMPATIBLE \
    --guest-os-features=SECURE_BOOT \
    --storage-location=us

echo "[+] ALL DONE!"
echo "You can now create a VM with:"

echo "gcloud compute instances create zorin-vm --image=$IMAGE_NAME --machine-type=e2-medium"
