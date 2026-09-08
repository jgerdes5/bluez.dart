/// Types of Bluetooth address.
enum BlueZAddressType { public, random }

/// Types of writes to a GATT characteristic.
enum BlueZGattCharacteristicWriteType { command, request, reliable }

/// Defines how a GATT characteristic value can be used.
enum BlueZGattCharacteristicFlag {
  broadcast,
  read,
  writeWithoutResponse,
  write,
  notify,
  indicate,
  authenticatedSignedWrites,
  extendedProperties,
  reliableWrite,
  writableAuxiliaries,
  encryptRead,
  encryptWrite,
  encryptAuthenticatedRead,
  encryptAuthenticatedWrite,
  secureRead,
  secureWrite,
  authorize,
}

/// The capability of an agent registered with [BlueZClient.registerAgent].
/// * [displayOnly] - can only display information from the device.
/// * [displayYesNo] - able to display information from the device and respond with yes/no answers.
/// * [keyboardOnly] - only able to respond with pin code / passcode information.
/// * [noInputNoOutput] - not able to display information or provide information to devices.
/// * [keyboardDisplay] - able to display information from the device and respond with ping code / passcode information.
enum BlueZAgentCapability {
  displayOnly,
  displayYesNo,
  keyboardOnly,
  noInputNoOutput,
  keyboardDisplay,
}

/// The playback status of a [BlueZMediaPlayer].
///
/// [forwardSeek] and [reverseSeek] mean the remote transport is moving, not
/// that it has stopped - a player fast-forwarding is still playing.
/// [error] is reported when the property is absent or unrecognised, which
/// happens on a player object that has not published a status yet.
enum BlueZMediaPlayerStatus {
  playing,
  stopped,
  paused,
  forwardSeek,
  reverseSeek,
  error,
}

/// Whether a [BlueZMediaPlayer]'s equalizer is engaged.
enum BlueZMediaPlayerEqualizer { off, on }

/// The repeat mode of a [BlueZMediaPlayer].
enum BlueZMediaPlayerRepeat { off, singleTrack, allTracks, group }

/// The shuffle mode of a [BlueZMediaPlayer].
enum BlueZMediaPlayerShuffle { off, allTracks, group }

/// The scan mode of a [BlueZMediaPlayer].
enum BlueZMediaPlayerScan { off, allTracks, group }

/// The state of a [BlueZMediaTransport].
enum BlueZMediaTransportState { idle, pending, active, broadcasting }

/// Type of advertisement.
enum BlueZAdvertisementType {
  broadcast,
  peripheral,
}
