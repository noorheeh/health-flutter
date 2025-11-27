package cachet.plugins.health

import androidx.health.connect.client.records.metadata.Metadata

/**
 * Returns a user-friendly description of the device that produced the Health Connect record.
 * Combines manufacturer and model when available and ignores empty values.
 */
internal fun Metadata.deviceLabel(): String? {
    val recordDevice = device ?: return null

    val manufacturer = recordDevice.manufacturer?.trim()?.takeIf { it.isNotEmpty() }
    val model = recordDevice.model?.trim()?.takeIf { it.isNotEmpty() }

    val parts = listOfNotNull(manufacturer, model)
    if (parts.isNotEmpty()) {
        return parts.joinToString(" ")
    }

    return manufacturer ?: model
}
