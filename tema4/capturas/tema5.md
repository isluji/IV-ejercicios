
# Ejercicios Tema 4 (Virtualización ligera usando contenedores)

## Ejercicio 1

### Instalar los paquetes necesarios para usar KVM. Se pueden seguir [estas instrucciones](https://wiki.debian.org/KVM#Installation). Ya lo hicimos en el primer tema, pero volver a comprobar si nuestro sistema está preparado para ejecutarlo o hay que conformarse con la paravirtualización.

Primero, voy a comprobar si mi sistema cumple los requisitos para ejecutar este tipo de virtualización. El componente que se analiza es el procesador, pues es quien debe incorporar las tecnologías necesarias.

El procesador de mi portátil posee y tiene habilitada la tecnología VT-x de Intel (flag vmx). Se trata de un procesador Intel® Core™ i5-2450M CPU @ 2.50GHz × 4. Esta es la salida de la orden:

![Resultado orden grep del ej. 4](./capturas/ej4.png)


## Ejercicio 5

### 5.1. Comprobar si el núcleo instalado en tu ordenador contiene este módulo del kernel usando la orden kvm-ok.

La herramienta kvm-ok está contenida en el paquete cpu-checker, el cual he tenido que instalar para poder usarla.

![Resultado orden kvm-ok](./capturas/ej5_1.png)
