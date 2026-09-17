package mx.edu.prepa13.inventario_maker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Canal de importancia alta: los avisos (solicitudes, alertas) aparecen arriba de la pantalla y suenan.
        // El servidor manda cada aviso a este canal ("avisos").
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canal = NotificationChannel("avisos", "Avisos del laboratorio", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Solicitudes nuevas, cancelaciones, alertas y reportes"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
        }
    }
}
