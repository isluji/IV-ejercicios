
# Ejercicios Tema 4 (Virtualización ligera usando contenedores)

## Ejercicio 1

### Instalar los paquetes necesarios para usar KVM. Se pueden seguir [estas instrucciones](https://wiki.debian.org/KVM#Installation). Ya lo hicimos en el primer tema, pero volver a comprobar si nuestro sistema está preparado para ejecutarlo o hay que conformarse con la paravirtualización.

Primero, voy a comprobar si mi sistema cumple los requisitos para ejecutar este tipo de virtualización. El componente que se analiza es el procesador, pues es quien debe incorporar las tecnologías necesarias.

Mi portátil consta de un procesador Intel® Core™ i5-2450M CPU @ 2.50GHz × 4. Utilizando el fichero ```/proc/cpuinfo``` y la herramienta ```kvm-ok``` (contenida en el paquete **cpu-checker**), he podido comprobar que este procesador soporta tanto la virtualización x86 (Intel VT-x) como la virtualización KVM.

![Comprobación de virtualización x86](./capturas/ej1_1.png)

![Comprobación de virtualización KVM](./capturas/ej1_2.png)

Por tanto, podré utilizar la tecnología KVM y no tendré que recurrir a la paravirtualización. Para utilizar esta tecnología, he tenido que instalar estos paquetes (todos se instalan de forma trivial con ```apt-get```):

* **qemu-kvm**: Hipervisor
* **libvirt-bin**: Daemon que carga el módulo KVM apropiado según el procesador
* Para crear las máquinas virtuales, podemos usar tanto la CLI **virtinst** como la GUI **virt-manager**


## Ejercicio 2

### 1. Crear varias máquinas virtuales con algún sistema operativo libre tal como Linux o BSD. Si se quieren distribuciones que ocupen poco espacio con el objetivo principalmente de hacer pruebas se puede usar CoreOS (que sirve como soporte para Docker); GALPon Minino, hecha en Galicia para el mundo; Damn Small Linux, SliTaz (que cabe en 35 megas) y ttylinux (basado en línea de órdenes solo).

### 2. Hacer un ejercicio equivalente usando otro hipervisor como Xen, VirtualBox o Parallels.

1. Voy a instalar dos máquinas virtuales: una con Damn Small Linux y otra con SliTaz.

Para crear una máquina virtual, lo primero es crear un disco duro virtual. Creamos dos ficheros **QCOW2** utilizando la herramienta ```qemu-img``` (como estas distribuciones son muy ligeras, no hace falta asignarles mucho espacio):

![Creando los discos duros virtuales](./capturas/ej2-1_1.png)

Ya tenemos todos los requisitos, por lo que podemos lanzar las MV con KVM ejecutando los siguientes comandos:

* Lanzar MV Damn Small Linux: ```qemu-system-x86_64 -hda vhd_dsl.qcow2 -cdrom /media/isluji/ISMAEL/Informatica/so/damn-small-linux-4.11.rc2.iso```

* Lanzar MV SliTaz: ```qemu-system-x86_64 -hda vhd_slitaz.qcow2 -cdrom /media/isluji/ISMAEL/Informatica/so/slitaz-4.0.iso```

----------------------

Primero voy a instalar la MV con Damn Small Linux. Este SO está diseñado para usarse como LiveCD; de todas formas, es posible su instalación en disco duro de dos formas: el método "tradicional", que lo instala como una distro de Debian, y el método "frugal", que instala el sistema de archivos comprimido y lo carga en memoria con cada arranque tal como haría un LiveCD. Los desarrolladores recomiendan este último método, puesto que ofrece varias ventajas, como la posibilidad de actualizar el SO sin reinstalarlo desde 0 y de utilizar ciertas aplicaciones diseñadas específicamente para su uso en un entorno frugal/LiveCD.

Para instalar DSL, primero hay que crear una partición en el disco duro virtual. Para ello, utilizamos la herramienta **cfdisk**, ejecutándola sobre el dispositivo virtual que hemos especificado al arrancar la MV (**hda** => ```cfdisk /dev/hda```). Una vez dentro, creamos una tabla de particiones vacía; a continuación, creamos una partición primaria con ***New*** y le activamos el flag ***Bootable***; y, finalmente, sobrescribimos la tabla de particiones con ***Write***.

![Creando una partición con cfdisk](./capturas/ej2-1_2.png)

Ahora podemos utilizar la partición recién creada (**hda1**) para instalar el SO. Para ello, accedemos a la herramienta ***Frugal Install***. También podemos crear otra partición opcional para almacenar las extensiones MyDSL (aplicaciones que se instalan en disco duro); si no lo hacemos, tendremos que copiar manualmente estas extensiones al almacenamiento permanente si queremos preservarlas.

![Instalar DSL en disco duro](./capturas/ej2-1_3.png)

----------------------

Procedo a lanzar la segunda máquina virtual, esta vez con la distro SliTaz. Esta distro también está diseñada para su uso como LiveCD/USB, y a simple vista no he encontrado ninguna opción o herramienta para instalarlo en el disco duro. Buscando en la documentación, he descubierto que sí se puede [instalar de diversas formas](http://doc.slitaz.org/en:handbook:installation), pero no lo considero necesario para este ejercicio.

![Captura de la MV con SliTaz (1)](./capturas/ej2-1_4.png)

![Captura de la MV con SliTaz (2)](./capturas/ej2-1_5.png)

----------------------

2. De los hipervisores mencionados, voy a utilizar **VirtualBox**.

![Creación de MV con VirtualBox (1)](./capturas/ej2-2_1.png)

Al tratarse de una GUI, la creación del disco duro virtual está incluida en el wizard de creación de la máquina virtual.

![Creación de MV con VirtualBox (2)](./capturas/ej2-2_2.png)

También podemos utilizar uno de los discos duros creados anteriormente, pero en este caso vamos a crear dos nuevos HD virtuales con el formato propio de VirtualBox, **VDI (VirtualBox Disk Image)**.

![Creación de MV con VirtualBox (3)](./capturas/ej2-2_3.png)

Elegimos la opción "asignado dinámicamente" para que el disco duro virtual sólo ocupe en el real el espacio que se vaya llenando al instalar cosas en la MV (hasta un máximo que fijamos nosotros).

![Creación de MV con VirtualBox (4)](./capturas/ej2-2_4.png)

Le asignamos el nombre y el tope de espacio que queramos y creamos el disco duro virtual. 

![Creación de MV con VirtualBox (5)](./capturas/ej2-2_5.png)

Con esto finalizamos el wizard, ya tenemos la MV creada y nos aparecerá en la lista de MVs de VirtualBox.

Realizamos el mismo proceso para crear la MV de SliTaz. Desde la pantalla principal de VirtualBox, podemos lanzar las MVs que hemos creado y ver sus características.

![Lista de MVs de VirtualBox](./capturas/ej2-2_6.png)

Al arrancarlas, nos pedirá que seleccionemos la ISO que usaremos para cargar el SO.

![Seleccionar ISO con el sistema operativo](./capturas/ej2-2_7.png)

Una vez seleccionamos la ISO, ya podemos arrancar la MV e instalar el SO en el disco duro virtual si así lo deseamos.

![Lanzar MV con DSL en VirtualBox](./capturas/ej2-2_8.png)

![Lanzar MV con SliTaz en VirtualBox](./capturas/ej2-2_9.png)


## Ejercicio 3

### Crear un benchmark de velocidad de entrada/salida y comprobar la diferencia entre usar paravirtualización y arrancar la máquina virtual simplemente con ```qemu-system-x86_64 -hda /media/Backup/Isos/discovirtual.img```.

**NO REALIZADO**


## Ejercicio 4

### Crear una máquina virtual Linux con 512 megas de RAM y entorno gráfico LXDE a la que se pueda acceder mediante VNC y ssh.

Esta vez crearé la máquina virtual utilizando **VMM (Virtual Machine Manager)**, la GUI para QEMU/KVM instalada mediante el paquete ***virt-manager***. El proceso de creación de una MV es similar al seguido en VirtualBox, por lo que no voy a describirlo paso a paso, sino que me centraré en la conexión mediante VNC y SSH.

Como dispongo de una ISO de Ubuntu Server 12.04 de 32 bits, la utilizaré para "convertirla en Lubuntu" cambiando el gestor de ventanas de serie (GNOME) por LXDE, en vez de descargarme una nueva distro.

![Cambiar entorno de escritorio en Ubuntu Server](./capturas/ej4_1.png)

Una vez instalados estos paquetes, podemos acceder al escritorio LXDE con ```startx```.

![Escritorio de Ubuntu Server con LXDE](./capturas/ej4_2.png)

Para realizar las conexiones, vamos a instalar en la MV los servidores de OpenSSH y TightVNC:

```bash
sudo apt-get install openssh-server tightvncserver
```

Tras instalarlo, procedemos a realizar la configuración inicial de TightVNC ejecutando el comando ```vncserver```, en la que tendremos que crear un usuario con el que poder conectar. Al finalizar, se lanza una instancia de escritorio VNC en el puerto 5901 (escritorio :1).

Como el SO de la MV es Ubuntu Server, el servidor VNC viene configurado por defecto para GNOME, que es el gestor de ventanas de serie con Ubuntu. Como he cambiado a LXDE, tengo que cambiar la configuración para poder lanzar el escritorio automáticamente al lanzar el servidor VNC. Para ello, primero he tenido que apagar el servidor:

```bash
vncserver -kill :1
```

![Configuración inicial de tightvncserver](./capturas/ej4_3.png)

Una vez hecho esto, ya puedo editar el fichero de configuración localizado en ~/.vnc/xstartup. He sustituido la línea ```/etc/X11/Xsession``` por esta otra: ```/usr/bin/startlxde```.

![Configuración de arranque de tightvncserver](./capturas/ej4_4.png)

Para conectar con la MV, en mi host he instalado el cliente Vinagre, que soporta tanto SSH como VNC, entre otros.

Primero, observamos cual es la IP de la MV utilizando el comando ```ifconfig```:

![Interfaces de red de la MV](./capturas/ej4_5.png)

Listo. Ya podemos conectar mediante SSH desde nuestro host utilizando Vinagre:

![Conexión a la MV mediante SSH (1)](./capturas/ej4_6.png)

![Conexión a la MV mediante SSH (2)](./capturas/ej4_7.png)

Para conectarnos mediante VNC, además de la IP hemos de indicar el ID del escritorio al que nos vamos a conectar (o el puerto equivalente). En este caso, es el :1 (puerto 5901).

![Conexión a la MV mediante VNC (1)](./capturas/ej4_8.png)

Nos pedirá que introduzcamos nuestra contraseña de acceso de VNC. Finalmente, ya podemos "trastear" en el escritorio de nuestra MV desde nuestro host.

![Conexión a la MV mediante VNC (2)](./capturas/ej4_9.png)


## Ejercicio 5

### Crear una máquina virtual Ubuntu e instalar en ella alguno de los servicios que estamos usando en el proyecto de la asignatura.

Para este ejercicio, he creado una máquina virtual con Ubuntu 14.04 utilizando VMM, puesto que la MV que creé en el anterior ejercicio tiene un kernel demasiado antiguo para usar Docker. Primero, instalo git y clono el repositorio de mi proyecto.

![Instalar git en la MV](./capturas/ej5_1.png)

Una vez hecho esto, ejecuto el [script de instalación de Docker en Ubuntu](https://github.com/isma94/Travial-Web/blob/master/scripts/installDocker_Ubuntu.sh) que creé para el hito 4 de la asignatura. Una vez instalado Docker, puedo ejecutar el [script que creé para desplegar la aplicación mediante contenedores Docker](https://github.com/isma94/Travial-Web/blob/master/compose/deployDockerCompose_dev.sh) en la MV.

![Instalar Docker en la MV mediante un script](./capturas/ej5_2.png)

En este caso, el script no ha funcionado, pues al tratarse de una máquina virtual, no funciona con Docker tal cual lo hace en un host real. En este caso, hay que instalar docker-machine en el host para gestionar el despliegue de contenedores en sus máquinas virtuales. He intentado hacerlo pero no lo he conseguido, y no dispongo de demasiado tiempo así que lo dejaré por aquí.

![Intento de conexión con Docker Machine](./capturas/ej5_3.png)


## Ejercicio 6

### Instalar una máquina virtual con Linux Mint para el hipervisor que tengas instalado.

**NO REALIZADO**
