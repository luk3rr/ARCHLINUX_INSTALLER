#!/bin/bash

. ./functions.sh
. ./constants.sh

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

# Teste de conexão com a internet
echo "Verificando conexão com a internet..."
if ping -c 1 archlinux.org &> /dev/null; then
    echo "Conexão com a internet estabelecida."
else
    echo "Conexão com a internet falhou. Conecte-se a uma rede."
	echo "Iniciando iwctl..."
    iwctl
    check_success
    # Verifique novamente após a tentativa de conexão Wi-Fi
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "Conexão com a internet estabelecida após conectar ao Wi-Fi."
    else
        echo "Falha ao conectar à internet. Verifique a conexão e tente novamente."
        exit 1
    fi
fi

# Particionamento do disco
echo "Iniciando particionamento do disco..."
choose_disk

read -p "Deseja utilizar LVM on LUKS? (s/n): " use_luks

# Salvar a informação sobre utilizar LVM on LUKS
# para uso posterior no script chroot
echo "use_luks=$use_luks" >> ./constants.sh
echo "disco_escolhido=$disco_escolhido" >> ./constants.sh

if [ "$use_luks" = "s" ]; then
	partition_disk

	# Verifique se o disco escolhido está sendo usado
	echo "Verificando volumes montados e swap ativos..."

	# Desativar swap
	# Capturar o caminho da partição swap ativa
	swap_device=$(swapon --show | grep -E '/dev/' | awk '{print $1}')

	# Se houver uma partição swap ativa, desativá-la
	if [ -n "$swap_device" ]; then
		echo "Desativando swap em $swap_device..."
		swapoff "$swap_device"
		check_success
	fi

	# Desmontar partições montadas
	if mount | grep -q "/mnt"; then
		echo "Desmontando partições..."
		umount -R /mnt
		check_success
	fi

	# Fechar volume LUKS/LVM se estiver aberto
	if cryptsetup status cryptlvm >/dev/null 2>&1; then
		echo "Fechando volume criptografado existente..."
		vgchange -a n vg0  # Desativa o volume group
		cryptsetup close cryptlvm
		check_success
	fi
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
read -p "Você usa processador AMD ou Intel? (a/i): " user_processor

while [ "$user_processor" != "a" ] && [ "$user_processor" != "i" ]; do
	echo "Opção inválida. Tente novamente."
	read -p "Você usa processador AMD ou Intel? (a/i): " user_processor
done

if [ "$user_processor" = "a" ]; then
	base_system_packages="$base_system_packages amd-ucode"
elif [ "$user_processor" = "i" ]; then
	base_system_packages="$base_system_packages intel-ucode"
fi

echo "Instalando o sistema base..."
pacstrap /mnt $base_system_packages
check_success

echo "Gerando arquivo fstab..."
genfstab -U -p /mnt >>/mnt/etc/fstab
check_success

echo "Copiando o script de comandos para o ambiente chroot..."
cp chroot-commands.sh functions.sh constants.sh /mnt/root
chmod +x /mnt/root/chroot-commands.sh /mnt/root/functions.sh /mnt/root/constants.sh

echo "Entrando no sistema instalado..."
arch-chroot /mnt /root/chroot-commands.sh

echo "Saindo do chroot e limpando..."
rm /mnt/root/chroot-commands.sh /mnt/root/functions.sh /mnt/root/constants.sh

