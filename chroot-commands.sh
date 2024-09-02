#!/bin/bash

. /root/functions.sh
. /root/constants.sh

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
read -p "Digite o nome do seu computador: " hostname
echo "$hostname" >/etc/hostname

cat <<EOF >>/etc/hosts
127.0.0.1         localhost.localdomain            localhost
::1               localhost.localdomain            localhost
127.0.1.1         $hostname.localdomain            $hostname
EOF
check_success

echo "Configurando senha de root..."
while true; do
    echo "Digite a senha para o usuário root:"
    if passwd; then
        echo "Senha root configurada com sucesso!"
        break
    else
        echo "Erro ao configurar a senha root. Tente novamente."
    fi
done

echo "Criando usuário..."

confirm_user_name="n"
while [ "$confirm_user_name" != "s" ]; do
	read -p "Digite seu nome de usuário: " username
	echo "Usuário: $username"
	read -p "Confirma? (s/n): " confirm_user_name
done

useradd -m -g users -G wheel "$username"

while true; do
    echo "Digite a senha para o usuário $username:"
    if passwd "$username"; then
        echo "Senha configurada com sucesso!"
        break
    else
        echo "Erro ao configurar a senha. Tente novamente."
    fi
done

if [ "$use_luks" = "s" ]; then
	echo "Editando /etc/mkinitcpio.conf para LVM on LUKS..."
    sed -i '/^HOOKS=/s/^/#/' /etc/mkinitcpio.conf
	echo 'HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 encrypt filesystems fsck)' >> /etc/mkinitcpio.conf

	mkinitcpio -p linux
	check_success
fi

echo "Instalando pacotes básicos..."
pacman -Syu --noconfirm $basic_packages
check_success

# TODO: Verificar necessidade, visto que o pacote mesa já é instalado
read -p "Você usa Nvidia? (s/n): " use_nvidia
if [ "$use_nvidia" = "s" ]; then
	pacman -S --noconfirm nvidia
	check_success
fi

echo "Configurando sudoers..."
echo "$username ALL=(ALL) ALL" >>/etc/sudoers
check_success

# Configurando Bootloader
echo "Configurando Grub..."

# Modificar o arquivo de configuração do GRUB para incluir o UUID da partição criptografada
if [ "$use_luks" = "s" ]; then
	luks_uuid=$(blkid -s UUID -o value /dev/"${disco_escolhido}2")
	sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"|GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${luks_uuid}:cryptlvm root=/dev/mapper/vg0-root |" /etc/default/grub
fi

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

echo "Instalação concluída. Execute 'reboot' para reiniciar o sistema."
