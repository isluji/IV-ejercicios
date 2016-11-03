'use strict';

module.exports = function(grunt) {

  // Configuración del proyecto
  // (definición de la tarea => en este caso, generar la documentación)
  grunt.initConfig({
    // 1. Indicamos cuál es nuestro package.json
    pkg: grunt.file.readJSON('package.json'),
    // 2. Definimos la tarea llamada docco...
    docco: {
      // 3. ...que a su vez tiene una subtarea llamada debug
      // (toma los fuentes contenidos en el array indicado
      // y deposita la salida en el directorio que le indicamos)
  	  debug: {
    	  src: ['*.js'],
    	  options: {
    		  output: 'docs/'
    	  }
  	  }
    }
  });

  // CARGA DE LA TAREA
  // Carga el plugin de grunt necesario para ejecutar docco
  grunt.loadNpmTasks('grunt-docco');

  // REGISTRO DE LA TAREA
  // Indicamos que la tarea que ejecuta docco es la que se ejecutará
  // por defecto simplemente ejecutando grunt
  grunt.registerTask('default', ['docco']);
};
