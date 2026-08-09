# 📱 Tesis Hipertrofia App (BioSmart Coach)

Este repositorio contiene el código fuente de la aplicación móvil multiplataforma desarrollada para el proyecto de tesis **BioSmart Coach**. La aplicación está diseñada para revolucionar el seguimiento del entrenamiento físico mediante el análisis de postura en tiempo real y la generación de reportes inteligentes.

## 🏛️ Arquitectura del Proyecto

El desarrollo está estructurado bajo un modelo estricto de **Arquitectura de 3 Capas**, diseñado para maximizar el rendimiento y mantener el código organizado:

*   **Capa 1: Presentación y Lógica:** Construida íntegramente en Flutter (Dart). Se encarga de renderizar la interfaz de usuario (UI), capturar las interacciones y manejar la lógica interna y de estado de la aplicación de cara al usuario.
*   **Capa 2: Servicios y APIs:** Actúa como el puente de comunicación. Aquí se consume el backend de alto rendimiento construido en **Deno**, se integran los modelos de visión artificial (**Google ML Kit**) para el mapeo de poses, y se gestionan las peticiones a los modelos de **IA** (OpenAI) para la generación de reportes.
*   **Capa 3: Base de Datos:** Capa dedicada exclusivamente a la persistencia, almacenamiento de métricas y gestión de información del sistema, apoyada por servicios en la nube como **Supabase**.

## 🛠️ Stack Tecnológico e Integraciones

*   **Frontend Móvil:** Desarrollado con **Flutter** (Dart), compilando nativamente para dispositivos móviles.
*   **Backend:** API REST externa de alto rendimiento construida sobre **Deno**.
*   **Visión Artificial:** Integración nativa de **Google ML Kit** para el reconocimiento, mapeo y análisis de posturas corporales durante los ejercicios.
*   **Inteligencia Artificial (IA):** Uso de la API de **OpenAI** para procesar los datos del entrenamiento y generar reportes analíticos personalizados para el usuario.
*   **Servicios Cloud:** Gestión de base de datos y almacenamiento (BaaS).

## 🚀 Características Principales

*   **Análisis Biomecánico:** Detección de posturas en tiempo real gracias a los modelos de machine learning ejecutados desde la Capa de Servicios.
*   **Reportes con IA:** Generación automatizada de feedback detallado sobre el rendimiento físico del usuario.
*   **Código Modular (3 Capas):** Permite actualizar la interfaz (Capa 1) o modificar la lógica de la IA (Capa 2) de forma totalmente independiente sin afectar a la base de datos (Capa 3).

## ⚙️ Instalación y Ejecución Local

Para levantar este proyecto, asegúrate de tener el [SDK de Flutter](https://flutter.dev/docs/get-started/install) instalado:

1. Clona el repositorio e instala las dependencias:
   ```bash
   flutter pub get
   
Configura las variables de entorno necesarias para las claves de la IA y la conexión a la base de datos.

Ejecuta la aplicación en tu emulador o dispositivo físico:
```bash
flutter run
