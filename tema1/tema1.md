# EJERCICIOS TEMA 1

## Ejercicio 1

### Consultar en el catálogo de alguna tienda de informática el precio de un ordenador tipo servidor y calcular su coste de amortización a cuatro y siete años. [Consultar este artículo en Infoautónomos sobre el tema.](http://infoautonomos.eleconomista.es/consultas-a-la-comunidad/988/)

Los bienes (activos) de una empresa pierden valor a lo largo del tiempo, debido al deterioro debido al uso o simplemente a su obsolescencia por la mejora de la tecnología. Esto se conoce como amortización o depreciación.

Para calcular esta amortización, aplicamos el porcentaje de pérdida de valor establecido por Hacienda, que para equipos informáticos es de un máximo del 26% del precio del producto durante un período máximo de 10 años

https://www.pccomponentes.com/hp-proliant-bl460c-gen9-e5-2620v3

Precio del servidor = 2120€
26% de 2120€ = 551,2€

- Amortización a 4 años => 551,2€ x 4 = 2204,8€

- Amortización a 7 años => 551,2€ x 7 = 3858,4€


## Ejercicio 2

### Usando las tablas de precios de servicios de alojamiento en Internet y de proveedores de servicios en la nube, Comparar el coste durante un año de un ordenador con un procesador estándar (escogerlo de forma que sea el mismo tipo de procesador en los dos vendedores) y con el resto de las características similares (tamaño de disco duro equivalente a transferencia de disco duro) en el caso de que la infraestructura comprada se usa sólo el 1% o el 10% del tiempo.

Vamos a comparar el servicio en la nube Microsoft Azure (concretamente, su instancia A7) con el servidor dedicado SP-64-S del proveedor OVH.

- Características Azure A7:

**CPU:** Intel Xeon E5 (4 núcleos)
**RAM:** 56 GB
**Transferencia de disco:** 2 TB
**Precio:** 1,1891€/h

- Características OVH SP-64-S:

**CPU:** Intel Xeon E5 (4 núcleos)
**RAM:** 64 GB
**Disco duro:** 4 TB
**Precio:** 120,99€/mes

El servicio en la nube Azure tiene el doble de capacidad de disco duro pero es muy similar en los demás apartados. Voy a calcular el coste del servicio en la nube proporcional al uso indicado y compararlo con el del servidor dedicado (que no se puede fraccionar, puesto que se paga una cuota fija mensual independientemente del uso).

- Uso de un 1% durante un año:

1 % de un año = 87,6h

1,19€/h x 87,6h = 104,24€

- Uso de un 10% durante un año:

10 % de un año = 876h

1,19€/h x 876€ = 1042,44€

Como podemos observar, el servicio en la nube es mucho más económico en esta tesitura, puesto que pagamos por horas de servicio y no una cantidad mensual fija. Mientras que con este servicio pagamos 104,24€ por un uso de un 1% en un año y 1042,44€ por un uso de un 10 % en un año, con el servidor OVH pagamos 121€ x 12 = 1452€ al año independientemente del uso, por lo que nos saldría bastante más caro en ambos casos. Para un elevado tiempo de uso del servicio, sí nos convendría este último, puesto que compensaríamos dicho coste con el uso y nos saldría más barato que el servicio en la nube.


## Ejercicio 3

### 3.1. ¿Qué tipo de virtualización usarías en cada caso? [Comentar en el foro.](https://github.com/JJ/IV16-17/issues/1)

- **Virtualización plena:** Los estudiantes que sólo tengan Windows y no dispongan de particiones libres, pueden instalar una máquina virtual de alguna distro de Linux en Windows para realizar los ejercicios y prácticas de Infraestructura Virtual.

- **Virtualización parcial:** Los hipervisores de virtualización (como VMWare o VirtualBox) utilizan archivos VHD (Virtual Hard Disk) que funcionan como una abstracción de una cierta cantidad de espacio en el disco del anfitrión, "empaquetándolo" para que parezca un disco duro como tal a ojos del SO invitado y lo interprete como un sistema de archivos.

- **Paravirtualización:** Es el sistema utilizado por el software Xen para lograr un mayor rendimiento (2-8%) que con la virtualización plena (20%). Para ello, se necesita que el sistema operativo virtualizado cuente con una versión adaptada al API de Xen, de forma que las llamadas al sistema sean dirigidas al hipervisor en vez de al hardware, que no está presente en este caso.

- **Virtualización a nivel de sistema operativo:** El sistema de usuarios de algunos SO como Linux o Windows permite el uso de un mismo SO mediante diferentes cuentas, en las que cada usuario tiene su propia configuración del entorno y ve sólo sus aplicaciones y archivos, permaneciendo aislado de los demás. En este sistema, el usuario anfitrión es aquel con derechos de administrador, puesto que puede controlar y modificar los sistemas de los demás usuarios (invitados).

- **Virtualización de aplicaciones:** El emulador VirtualBoy Advance ejecuta juegos de la consola GameBoy Advance en un entorno aislado del SO sobre el que se ejecuta. No es una virtualización plena puesto que lo que se ejecuta son las aplicaciones y no el SO de la consola.

- **Virtualización de entornos de desarrollo:** Un desarrollador de Python puede necesitar ciertas versiones de determinadas librerías para un proyecto, mientras que para otro necesita otras versiones de dichas librerías. Para solucionar esto, se pueden crear entornos virtuales con las versiones necesarias para cada aplicación, de forma que previamente a trabajar con cada aplicación se pueda cargar su entorno correspondiente y se eviten problemas de incompatibilidades y conflictos.


### 3.2. Crear un programa simple en cualquier lenguaje interpretado para Linux, empaquetarlo con CDE y probarlo en diferentes distribuciones.

![Creación de paquete CDE y prueba en Ubuntu](tema1/ej3/ej3_ubuntu.png)

[FALTA PROBAR PAQUETE CDE EN OTRAS DISTROS DE LINUX]()


## Ejercicio 4

### Comprobar si el procesador o procesadores instalados tienen estos flags. ¿Qué modelo de procesador es? ¿Qué aparece como salida de esa orden?

El procesador de mi portátil posee y tiene habilitada la tecnología VT-x de Intel (flag vmx). Se trata de un procesador Intel® Core™ i5-2450M CPU @ 2.50GHz × 4. Esta es la salida de la orden:

![Resultado orden grep del ej. 4]()


## Ejercicio 5

### 5.1. Comprobar si el núcleo instalado en tu ordenador contiene este módulo del kernel usando la orden kvm-ok.

La herramienta kvm-ok está contenida en el paquete cpu-checker, el cual he tenido que instalar para poder usarla.

![Resultado orden kvm-ok]()

### 5.2. Instalar un hipervisor para gestionar máquinas virtuales, que más adelante se podrá usar en pruebas y ejercicios.

He instalado 2 hipervisores, uno de los cuales ya había utilizado en ocasiones anteriores (VirtualBox) y otro que he instalado por sus amplias posibilidades (Xen).

![Instalación de VirtualBox y Xen](/tema1/ej)