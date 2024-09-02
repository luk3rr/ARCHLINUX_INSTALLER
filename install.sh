#!/bin/bash

. functions.sh
. constants.sh

# Configurações iniciais
echo "Carregando o layout de teclado brasileiro..."
loadkeys br-abnt2
check_success

echo "Verificando suporte EFI..."
if [ -d /sys/firmware/efi ]; then
	echo "EFI suportado."
else
	echo "EFI não suportado. Saindo..."
	exit 1
fi

# Conexão com a internet
if [ ! -f /sys/class/net/enp0s3 ]; then
	echo "Conexão cabeada não encontrada. Conecte-se a uma rede Wi-Fi."
	wifi-menu
	check_success
fi

echo "Verificando conexão com a internet..."
ping -c 3 google.com
check_success

# Particionamento do disco
echo "Iniciando particionamento do disco..."
choose_disk

read -r "Deseja utilizar LVM on LUKS? (s/n): " use_luks

if [ "$use_luks" = "s" ]; then
	partition_disk

	echo "Formatando a partição de boot..."
	mkfs.fat -F32 /dev/"${disco_escolhido}1"
	check_success

	echo "Criando container LUKS..."
	modprobe dm-crypt
	cryptsetup luksFormat /dev/"${disco_escolhido}2"
	cryptsetup open --type luks /dev/"${disco_escolhido}2" cryptlvm
	check_success

	echo "Criando volumes físicos e grupos LVM..."
	pvcreate /dev/mapper/cryptlvm
	vgcreate vg0 /dev/mapper/cryptlvm
	lvcreate -L 2G vg0 -n swap
	lvcreate -L 90G vg0 -n root
	lvcreate -l 100%FREE vg0 -n home
	check_success

	echo "Formatando sistemas de arquivos..."
	mkfs.ext4 /dev/vg0/root
	mkfs.ext4 /dev/vg0/home
	mkswap /dev/vg0/swap
	check_success

	echo "Montando os volumes..."
	mount /dev/vg0/root /mnt
	mount --mkdir /dev/vg0/home /mnt/home
	mount --mkdir /dev/"${disco_escolhido}1" /mnt/boot
	swapon /dev/vg0/swap
	check_success
else
	particionar_disco_sem_criptografia

	echo "Formatando as partições..."
	mkfs.fat -F32 /dev/"${disco_escolhido}1"
	mkfs.ext4 /dev/"${disco_escolhido}3"
	mkfs.ext4 /dev/"${disco_escolhido}4"
	mkswap /dev/"${disco_escolhido}2"
	check_success

	echo "Montando os volumes..."
	mount /dev/"${disco_escolhido}3" /mnt
	swapon /dev/"${disco_escolhido}2"
	mount --mkdir /dev/"${disco_escolhido}1" /mnt/boot
	mount --mkdir /dev/"${disco_escolhido}4" /mnt/home
	check_success
fi

# Configurações básicas
echo "Atualizando o relógio do sistema..."
timedatectl set-ntp true
check_success

# Instalação do sistema base
read -r "Você usa processador AMD ou Intel? (a/i): " user_processor

while [ "$user_processor" != "a" ] && [ "$user_processor" != "i" ]; do
	echo "Opção inválida. Tente novamente."
	read -r "Você usa processador AMD ou Intel? (a/i): " user_processor
done

if [ "$user_processor" = "a" ]; then
	base_system_packages="${base_system_packages} amd-ucode"
elif [ "$user_processor" = "i" ]; then
	base_system_packages="${base_system_packages} intel-ucode"
fi

echo "Instalando o sistema base..."
pacstrap /mnt "${base_system_packages}"
check_success

echo "Gerando arquivo fstab..."
genfstab -U -p /mnt >>/mnt/etc/fstab
check_success

echo "Entrando no sistema instalado..."
arch-chroot /mnt

echo "Configurando fuso horário..."
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
check_success

echo "Gerando o arquivo de localidade..."
echo "Descomentando en_US.UTF-8 em /etc/locale.gen..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
check_success

echo "Configurando variáveis de idioma e layout de teclado..."
echo "LANG=en_US.UTF-8" >/etc/locale.conf
echo "KEYMAP=br-abnt2" >/etc/vconsole.conf
check_success

echo "Configurando hostname..."
read -r "Digite o nome do seu computador: " hostname
echo "$hostname" >/etc/hostname

cat <<EOF >>/etc/hosts
127.0.0.1         localhost.localdomain            localhost
::1               localhost.localdomain            localhost
127.0.1.1         $hostname.localdomain            $hostname
EOF
check_success

echo "Configurando senha de root..."
passwd
check_success

echo "Criando usuário..."

confirm_user_name="n"
while [ "$confirm_user_name" != "s" ]; do
	read -r "Digite seu nome de usuário: " username
	echo "Usuário: $username"
	read -r "Confirma? (s/n): " confirm_user_name
done

useradd -m -g users -G wheel "$username"
passwd "$username"
check_success

if [ "$use_luks" = "s" ]; then
	echo "Editando /etc/mkinitcpio.conf para LVM on LUKS..."
	sed -i 's/HOOKS=(base udev autodetect modconf block filesystems fsck)/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
	mkinitcpio -p linux
	check_success
fi

echo "Instalando pacotes básicos..."
pacman -S --noconfirm "${basic_packages}"
check_success

# TODO: Verificar necessidade, visto que o pacote mesa já é instalado
read -r "Você usa Nvidia? (s/n): " use_nvidia
if [ "$use_nvidia" = "s" ]; then
	pacman -S --noconfirm nvidia
	check_success
fi

echo "Configurando sudoers..."
echo "$username ALL=(ALL) ALL" >>/etc/sudoers
check_success

# Configurando Bootloader
echo "Configurando Grub..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub --recheck
grub-mkconfig -o /boot/grub/grub.cfg
check_success

# Habilitar serviços de rede
echo "Habilitando serviços de rede..."
systemctl enable dhcpcd
systemctl enable iwd
systemctl enable NetworkManager
check_success

echo "Instalação concluída. Saindo do chroot..."
exit
umount -a
echo "Execute 'reboot' para reiniciar o sistema"
