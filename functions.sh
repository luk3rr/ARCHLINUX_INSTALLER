#!/usr/bin/env sh

# Função para verificar se o comando anterior foi executado com sucesso
check_success() {
	if [ $? -ne 0 ]; then
		echo "Erro ao executar o comando. Saindo..."
		exit 1
	fi
}

# Função para listar discos e permitir escolha do usuário
choose_disk() {
	echo "Listando discos disponíveis..."
	lsblk -d -n -o NAME,SIZE,MODEL

	while true; do
		read -p "Digite o nome do disco que deseja particionar: " disco_escolhido
		read -p "Você escolheu /dev/$disco_escolhido. Deseja continuar? [S/n] " confirmacao

		case $confirmacao in
		[Ss]*)
			break
			;;
		[Nn]*)
			continue
			;;
		*)
			echo "Por favor, digite S ou N."
			;;
		esac
	done
}

# Função para limpar e criar partições
partition_disk() {
	# Deleta todas as partições
	echo "Deletando todas as partições existentes em /dev/$disco_escolhido..."
	sgdisk --zap-all /dev/"$disco_escolhido"
	check_success

	echo "Criando nova tabela de partição..."
	sgdisk -o /dev/"$disco_escolhido"
	check_success

	echo "Criando partição EFI de 1GB..."
	sgdisk -n 1:0:+1G -t 1:ef00 /dev/"$disco_escolhido"
	check_success

	echo "Criando partição LVM no restante do disco..."
	sgdisk -n 2:0:0 -t 2:8e00 /dev/"$disco_escolhido"
	check_success

	echo "Tabela de partições criada com sucesso:"
	lsblk /dev/"$disco_escolhido"
}

# Função para particionamento sem criptografia
particionar_disco_sem_criptografia() {
	echo "Deletando todas as partições existentes em /dev/$disco_escolhido..."
	sgdisk --zap-all /dev/"$disco_escolhido"
	check_success

	echo "Criando nova tabela de partição..."
	sgdisk -o /dev/"$disco_escolhido"
	check_success

	echo "Criando partição EFI de 1GB..."
	sgdisk -n 1:0:+1G -t 1:ef00 /dev/"$disco_escolhido"
	check_success

	echo "Criando partição SWAP de 2GB..."
	sgdisk -n 2:0:+2G -t 2:8200 /dev/"$disco_escolhido"
	check_success

	echo "Criando partição ROOT de 90GB..."
	sgdisk -n 3:0:+90G -t 3:8300 /dev/"$disco_escolhido"
	check_success

	echo "Criando partição HOME no restante do disco..."
	sgdisk -n 4:0:0 -t 4:8300 /dev/"$disco_escolhido"
	check_success

	echo "Tabela de partições criada com sucesso:"
	lsblk /dev/"$disco_escolhido"
}
