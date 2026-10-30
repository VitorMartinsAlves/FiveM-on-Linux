# FiveM on Linux — CachyOS + Lutris + Rockstar Games Launcher

Aplicativo visual para preparar o **FiveM for GTA V Enhanced** usando a instalação existente do GTA V Enhanced e o prefixo Wine do Lutris onde você já usa o Rockstar Games Launcher. O jogo pode estar em outro HD: basta selecionar a pasta que contém `GTA5_Enhanced.exe`.

> **Experimental e sem suporte oficial a Linux.** O projeto não contorna anti-cheat. A preparação pode fazer o launcher abrir e carregar a lista de servidores, mas isso não garante que seja possível conectar a servidores públicos. O método Enhanced usado aqui foi demonstrado em uma instalação Steam; a combinação Rockstar Launcher + Lutris ainda pode exigir ajustes específicos do runner. Faça backup e use por sua conta e risco.

## Instalar com um comando no CachyOS

Abra o Konsole e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/VitorMartinsAlves/FiveM-on-Linux/main/install.sh | bash
```

Isso instala a interface em `~/.local/share/fivem-linux`, cria o comando `~/.local/bin/fivem-linux` e adiciona um atalho ao menu de aplicativos. Se `tkinter` não estiver instalado, o instalador oferece instalá-lo com `pacman`.

Depois, abra **FiveM on Linux** no menu ou execute:

```bash
~/.local/bin/fivem-linux
```

## Como preparar

1. Abra o GTA V Enhanced pelo Rockstar Games Launcher dentro do Lutris. Entre no modo história uma vez e feche o jogo e o launcher.
2. Abra FiveM on Linux. Confirme os três caminhos: **prefixo Lutris** (pasta com `drive_c` e `system.reg`), **pasta do GTA V Enhanced** (contém `GTA5_Enhanced.exe`) e **executável Wine** do mesmo runner configurado no Lutris.
3. Clique em **Preparar neste prefixo** e confirme. O script cria backup dos arquivos de registro antes de modificá-los, configura WebView2, prepara componentes do FiveM a partir dos manifests públicos da Cfx.re e cria um atalho no menu.
4. Clique em **Abrir FiveM** para iniciar. Na primeira execução, o cliente pode baixar vários GB de cache. Mantenha o disco com espaço livre.

A interface tenta detectar configurações do Lutris automaticamente, mas permite selecionar tudo manualmente. O GTA não é reinstalado. Se o Rockstar Launcher e o GTA usarem prefixos diferentes, selecione o prefixo que efetivamente contém o Rockstar Launcher/conta licenciada e que você usa para jogar.

## O que é alterado

- O prefixo Wine selecionado: registro WebView2, registro de instalação do FiveM e arquivos do cliente FiveM. A configuração `config.toml` recebe `[gta5enhanced] gamepath = "R:/"`, preservando as demais opções e criando backup do arquivo anterior.
- Um link de drive `R:` dentro do prefixo apontando para a pasta real do GTA.
- DLLs DirectX no prefixo, se estiverem disponíveis no runner selecionado. Os arquivos originais são copiados para o backup e as substituições Wine só são ativadas para os DLLs que realmente foram instalados.
- O cache e os backups ficam em `~/.local/share/fivem-linux/runtime`.
- Um atalho local em `~/.local/share/applications/fivem-enhanced-lutris.desktop`.

Não execute a preparação enquanto GTA, Rockstar Launcher ou outro programa estiver usando o prefixo. O script encerra o wineserver para que as alterações de registro sejam gravadas corretamente.

## Problemas conhecidos

- **Não detecta o jogo:** selecione manualmente a pasta que contém `GTA5_Enhanced.exe`, não a pasta anterior.
- **Não detecta o prefixo:** selecione a pasta raiz do prefixo Lutris; não selecione `drive_c`.
- **Janela preta:** o runner pode não expor os DLLs DXVK que o script procura. Ative DXVK na configuração do runner Lutris e confira a área Atividade.
- **Launcher abre, mas não conecta:** é uma limitação conhecida do FiveM Enhanced no Wine/Linux e pode não ser corrigível por caminhos ou configurações locais. O projeto não tenta ignorar o anti-cheat.
- **Runner Wine:** selecione o executável `bin/wine` e o `wineserver` correspondente do mesmo runner. O aplicativo não mistura um wineserver do sistema com um runner Lutris.

## Créditos

A pasta `third_party/akacross` contém scripts adaptados do projeto [akacross/fivem-enhanced-linux](https://github.com/akacross/fivem-enhanced-linux), sob licença MIT, preservada junto aos arquivos. O runtime WebView2 é obtido da Microsoft e os componentes FiveM são baixados dos manifests públicos da Cfx.re na hora da preparação. Este repositório não redistribui esses binários.

O projeto não é afiliado à Cfx.re, Rockstar Games, Valve ou Lutris.
