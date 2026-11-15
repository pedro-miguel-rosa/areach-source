import CoreBluetooth
import CryptoKit
import Foundation
import QuartzCore

struct NearbyBluetoothMessage: Codable {
  let authenticationCode: Data
  let credential: String
  let discoveryToken: Data?
  let eventScope: String
  let issuedAt: Double
  let kind: NearbyNetworkMessage.Kind
  let nonce: String
  let peerId: String
  let publicKey: String
  let signature: Data
  let transactionId: UUID?
}

final class NearbyBluetoothWakeService: NSObject {
  private static let controlCharacteristicUUID = CBUUID(
    string: "5A8CCF43-FA58-459A-B33B-CC7F0ABFCE38"
  )
  private static let wakeCharacteristicUUID = CBUUID(
    string: "9E35F6A2-6128-46DF-902A-73315005D6C8"
  )
  private static let connectionTimeout: DispatchTimeInterval = .seconds(5)
  private static let discoveryBatchDelay: DispatchTimeInterval = .milliseconds(150)
  private static let centralRestorationIdentifier =
    "io.areach.spatial.bluetooth-central"
  private static let peripheralRestorationIdentifier =
    "io.areach.spatial.bluetooth-peripheral"
  fileprivate static let chunkHeaderLength = 9
  private static let maximumMessageLength = 64 * 1024

  private let onMessageReceived: (NearbyBluetoothMessage) -> Void
  private let onFirstAdvertisement: () -> Void
  private let onRemoteWakeReceived: () -> Void
  private let onPeerSignalStrengthUpdated: (String, Int) -> Void
  private let queue: DispatchQueue

  private lazy var centralManager = CBCentralManager(
    delegate: self,
    queue: queue,
    options: [
      CBCentralManagerOptionRestoreIdentifierKey:
        Self.centralRestorationIdentifier,
      CBCentralManagerOptionShowPowerAlertKey: false,
    ]
  )
  private lazy var peripheralManager = CBPeripheralManager(
    delegate: self,
    queue: queue,
    options: [
      CBPeripheralManagerOptionRestoreIdentifierKey:
        Self.peripheralRestorationIdentifier,
      CBPeripheralManagerOptionShowPowerAlertKey: false,
    ]
  )

  private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
  private var discoveredPeripheralRSSI: [UUID: Int] = [:]
  private var smoothedPeripheralRSSI: [UUID: Double] = [:]
  private var lastAdvertisementAt: [UUID: CFTimeInterval] = [:]
  private var connectionFailureCount: [UUID: Int] = [:]
  private var firstDiscoveredAt: [UUID: CFTimeInterval] = [:]
  private var completedConnectionIds = Set<UUID>()
  private var controlCharacteristics: [UUID: CBCharacteristic] = [:]
  private var incomingCentralChunks: [UUID: BluetoothChunkAccumulator] = [:]
  private var incomingPeripheralChunks: [UUID: BluetoothChunkAccumulator] = [:]
  private var notificationChunks: [UUID: [Data]] = [:]
  private var pendingMessagesByPeerId: [String: [NearbyBluetoothMessage]] = [:]
  private var pendingWriteChunks: [UUID: [Data]] = [:]
  private var peerIdsByCentralId: [UUID: String] = [:]
  private var peerIdsByPeripheralId: [UUID: String] = [:]
  private var peripheralsByPeerId: [String: CBPeripheral] = [:]
  private var remoteCentrals: [UUID: CBCentral] = [:]
  private var wakeCharacteristics: [UUID: CBCharacteristic] = [:]
  private var writeInFlightPeripheralIds = Set<UUID>()
  private var connectingPeripheralIds = Set<UUID>()
  private var connectionTimeouts: [UUID: DispatchWorkItem] = [:]
  private var connectionBatchWorkItem: DispatchWorkItem?
  private var connectionRetryWorkItem: DispatchWorkItem?
  private var connectionRetryDeadline: CFTimeInterval?
  private var advertisementExpiryWorkItem: DispatchWorkItem?
  private var advertisementExpiryDeadline: CFTimeInterval?
  private var lastConnectionAttemptAt: [UUID: CFTimeInterval] = [:]
  private var isRunning = false
  private var credential = ""
  private var eventScope = ""
  private var localPeerId = ""
  private var signingPrivateKey: P256.Signing.PrivateKey?
  private var serviceUUID: CBUUID?
  private var transportKey = ""
  private var hasPublishedService = false
  private var localControlCharacteristic: CBMutableCharacteristic?
  private var discoveryIntensity: SpatialBluetoothDiscoveryIntensity = .foregroundNormal

  init(
    queue: DispatchQueue,
    onMessageReceived: @escaping (NearbyBluetoothMessage) -> Void,
    onFirstAdvertisement: @escaping () -> Void,
    onPeerSignalStrengthUpdated: @escaping (String, Int) -> Void,
    onRemoteWakeReceived: @escaping () -> Void
  ) {
    self.onMessageReceived = onMessageReceived
    self.onFirstAdvertisement = onFirstAdvertisement
    self.onPeerSignalStrengthUpdated = onPeerSignalStrengthUpdated
    self.onRemoteWakeReceived = onRemoteWakeReceived
    self.queue = queue

    super.init()
  }

  func start(
    eventScope: String,
    localPeerId: String,
    credential: String,
    transportKey: String,
    signingPrivateKey: P256.Signing.PrivateKey
  ) {
    isRunning = true
    self.credential = credential
    self.eventScope = eventScope
    self.localPeerId = localPeerId
    self.signingPrivateKey = signingPrivateKey
    self.transportKey = transportKey
    serviceUUID = Self.eventServiceUUID(eventScope: eventScope)

    _ = centralManager
    _ = peripheralManager
    updateScanning()
    publishService()
    scheduleConnections()
    scheduleAdvertisementExpiry()
  }

  func updateCredential(_ credential: String) {
    guard isRunning, !credential.isEmpty else {
      return
    }

    self.credential = credential
  }

  func setDiscoveryIntensity(
    intensity: SpatialBluetoothDiscoveryIntensity
  ) {
    guard discoveryIntensity != intensity else {
      return
    }

    discoveryIntensity = intensity
    refreshScanPolicy()
    scheduleConnections()
    scheduleAdvertisementExpiry()
  }

  func canSendMessage(to peerId: String) -> Bool {
    peripheralsByPeerId[peerId] != nil
      || peerIdsByCentralId.values.contains(peerId)
  }

  @discardableResult
  func send(
    _ kind: NearbyNetworkMessage.Kind,
    to peerId: String,
    discoveryToken: Data? = nil,
    transactionId: UUID? = nil
  ) -> Bool {
    guard
      isRunning,
      canSendMessage(to: peerId),
      let message = makeMessage(
        kind: kind,
        discoveryToken: discoveryToken,
        transactionId: transactionId
      )
    else {
      return false
    }

    if let centralId = peerIdsByCentralId.first(where: {
      $0.value == peerId
    })?.key,
      let central = remoteCentrals[centralId]
    {
      queueNotification(message, to: central)
      return true
    }

    pendingMessagesByPeerId[peerId, default: []].append(message)

    if let peripheral = peripheralsByPeerId[peerId] {
      if peripheral.state == .connected {
        flushPendingMessages(to: peripheral)
      }
    }

    scheduleConnections()

    return true
  }

  func refreshDiscovery() {
    guard isRunning else {
      return
    }

    centralManager.stopScan()
    lastConnectionAttemptAt.removeAll()
    updateScanning()
    scheduleConnections()
  }

  func stop() {
    isRunning = false
    centralManager.stopScan()
    connectionBatchWorkItem?.cancel()
    connectionBatchWorkItem = nil
    connectionRetryWorkItem?.cancel()
    connectionRetryWorkItem = nil
    connectionRetryDeadline = nil
    advertisementExpiryWorkItem?.cancel()
    advertisementExpiryWorkItem = nil
    advertisementExpiryDeadline = nil

    for timeout in connectionTimeouts.values {
      timeout.cancel()
    }

    for peripheral in discoveredPeripherals.values
    where peripheral.state == .connected || peripheral.state == .connecting {
      centralManager.cancelPeripheralConnection(peripheral)
    }

    if peripheralManager.state == .poweredOn {
      peripheralManager.stopAdvertising()
      peripheralManager.removeAllServices()
    }

    discoveredPeripherals.removeAll()
    discoveredPeripheralRSSI.removeAll()
    smoothedPeripheralRSSI.removeAll()
    lastAdvertisementAt.removeAll()
    connectionFailureCount.removeAll()
    firstDiscoveredAt.removeAll()
    completedConnectionIds.removeAll()
    controlCharacteristics.removeAll()
    incomingCentralChunks.removeAll()
    incomingPeripheralChunks.removeAll()
    notificationChunks.removeAll()
    pendingMessagesByPeerId.removeAll()
    pendingWriteChunks.removeAll()
    peerIdsByCentralId.removeAll()
    peerIdsByPeripheralId.removeAll()
    peripheralsByPeerId.removeAll()
    remoteCentrals.removeAll()
    wakeCharacteristics.removeAll()
    writeInFlightPeripheralIds.removeAll()
    connectingPeripheralIds.removeAll()
    connectionTimeouts.removeAll()
    lastConnectionAttemptAt.removeAll()
    serviceUUID = nil
    credential = ""
    eventScope = ""
    localPeerId = ""
    signingPrivateKey = nil
    transportKey = ""
    hasPublishedService = false
    localControlCharacteristic = nil
    discoveryIntensity = .foregroundNormal
  }

  private func updateScanning() {
    guard
      isRunning,
      centralManager.state == .poweredOn,
      let serviceUUID
    else {
      centralManager.stopScan()
      return
    }

    guard discoveryIntensity != .backgroundPassive else {
      centralManager.stopScan()
      return
    }

    guard !centralManager.isScanning else {
      return
    }

    let allowDuplicates = discoveryIntensity == .cameraAcquisition
    centralManager.scanForPeripherals(
      withServices: [serviceUUID],
      options: [
        CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates,
      ]
    )
  }

  private func refreshScanPolicy() {
    centralManager.stopScan()
    updateScanning()
  }

  private func publishService() {
    guard
      isRunning,
      peripheralManager.state == .poweredOn,
      let serviceUUID
    else {
      return
    }

    if hasPublishedService {
      if !peripheralManager.isAdvertising {
        peripheralManager.startAdvertising([
          CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])
      }
      return
    }

    let wakeCharacteristic = CBMutableCharacteristic(
      type: Self.wakeCharacteristicUUID,
      properties: [.write],
      value: nil,
      permissions: [.writeable]
    )
    let controlCharacteristic = CBMutableCharacteristic(
      type: Self.controlCharacteristicUUID,
      properties: [.notify, .write],
      value: nil,
      permissions: [.writeable]
    )
    let service = CBMutableService(type: serviceUUID, primary: true)
    service.characteristics = [controlCharacteristic, wakeCharacteristic]
    localControlCharacteristic = controlCharacteristic
    hasPublishedService = true
    peripheralManager.add(service)
  }

  private func connectToDiscoveredPeers() {
    cancelConnectionRetry()

    guard isRunning, discoveryIntensity != .backgroundPassive else {
      return
    }

    let occupiedConnectionIds = Set(
      discoveredPeripherals.values
        .filter { $0.state == .connected || $0.state == .connecting }
        .map(\.identifier)
    ).union(connectingPeripheralIds)
    let availableConnections = SpatialBluetoothTuning.maximumConcurrentConnections
      - occupiedConnectionIds.count
    guard availableConnections > 0 else {
      return
    }

    let now = CACurrentMediaTime()
    var nextRetryAt: CFTimeInterval?
    let candidates = discoveredPeripherals.values
      .filter { peripheral in
        guard
          peripheral.state == .disconnected,
          !connectingPeripheralIds.contains(peripheral.identifier)
        else {
          return false
        }

        let retryAt = SpatialBluetoothRetryPolicy.nextRetryAt(
          lastAttemptAt: lastConnectionAttemptAt[peripheral.identifier],
          delay: retryDelay(for: peripheral.identifier)
        )
        guard let retryAt else {
          // A newly discovered peripheral has never been attempted. It is
          // eligible immediately; zero/default timestamps must not delay the
          // first connection.
          return true
        }

        guard retryAt <= now else {
          nextRetryAt = min(nextRetryAt ?? retryAt, retryAt)
          return false
        }

        return true
      }
      .sorted { first, second in
        let firstPeerId = peerIdsByPeripheralId[first.identifier]
        let secondPeerId = peerIdsByPeripheralId[second.identifier]
        let firstHasPending = firstPeerId.map {
          pendingMessagesByPeerId[$0]?.isEmpty == false
        } ?? false
        let secondHasPending = secondPeerId.map {
          pendingMessagesByPeerId[$0]?.isEmpty == false
        } ?? false
        if firstHasPending != secondHasPending {
          return firstHasPending
        }

        let firstIsUnmapped = firstPeerId == nil
        let secondIsUnmapped = secondPeerId == nil
        if firstIsUnmapped != secondIsUnmapped {
          return firstIsUnmapped
        }

        let firstAge = now - (firstDiscoveredAt[first.identifier] ?? now)
        let secondAge = now - (firstDiscoveredAt[second.identifier] ?? now)
        if firstAge != secondAge {
          return firstAge > secondAge
        }

        let firstSignal = smoothedPeripheralRSSI[first.identifier]
          ?? -Double.greatestFiniteMagnitude
        let secondSignal = smoothedPeripheralRSSI[second.identifier]
          ?? -Double.greatestFiniteMagnitude
        if firstSignal != secondSignal {
          return firstSignal > secondSignal
        }

        return first.identifier.uuidString < second.identifier.uuidString
      }

    for peripheral in candidates.prefix(availableConnections) {
      connectingPeripheralIds.insert(peripheral.identifier)
      lastConnectionAttemptAt[peripheral.identifier] = now
      if firstDiscoveredAt[peripheral.identifier] == nil {
        firstDiscoveredAt[peripheral.identifier] = now
      }
      centralManager.connect(peripheral)
      scheduleConnectionTimeout(for: peripheral)
    }

    if candidates.count < availableConnections,
      let nextRetryAt
    {
      scheduleConnectionRetry(at: nextRetryAt)
    }
  }

  private func retryDelay(for peripheralId: UUID) -> CFTimeInterval {
    let failures = connectionFailureCount[peripheralId] ?? 0
    let base = discoveryIntensity == .cameraAcquisition
      ? SpatialBluetoothTuning.cameraFirstRetryDelay
      : SpatialBluetoothTuning.normalRetryDelay
    let multiplier = pow(2, Double(max(0, failures - 1)))
    let deterministicJitter = Double(peripheralId.uuidString.utf8.reduce(0) {
      ($0 + Int($1)) % 5
    }) * 0.1
    return min(
      SpatialBluetoothTuning.maximumRetryDelay,
      (failures == 0 ? base : base * multiplier) + deterministicJitter
    )
  }

  private func finishConnection(_ peripheral: CBPeripheral) {
    if completedConnectionIds.remove(peripheral.identifier) == nil {
      connectionFailureCount[peripheral.identifier] =
        (connectionFailureCount[peripheral.identifier] ?? 0) + 1
    } else {
      connectionFailureCount.removeValue(forKey: peripheral.identifier)
    }
    connectionTimeouts.removeValue(forKey: peripheral.identifier)?.cancel()
    connectingPeripheralIds.remove(peripheral.identifier)
    controlCharacteristics.removeValue(forKey: peripheral.identifier)
    incomingPeripheralChunks.removeValue(forKey: peripheral.identifier)
    pendingWriteChunks.removeValue(forKey: peripheral.identifier)
    writeInFlightPeripheralIds.remove(peripheral.identifier)
    wakeCharacteristics.removeValue(forKey: peripheral.identifier)

    if peripheral.state == .connected || peripheral.state == .connecting {
      centralManager.cancelPeripheralConnection(peripheral)
    }

    scheduleConnections()
    scheduleAdvertisementExpiry()
  }

  private func flushPendingMessages(to peripheral: CBPeripheral) {
    guard
      let peerId = peerIdsByPeripheralId[peripheral.identifier],
      let messages = pendingMessagesByPeerId.removeValue(forKey: peerId),
      !messages.isEmpty
    else {
      return
    }

    completedConnectionIds.insert(peripheral.identifier)

    for message in messages {
      queueWrite(message, to: peripheral)
    }
  }

  private func queueWrite(
    _ message: NearbyBluetoothMessage,
    to peripheral: CBPeripheral
  ) {
    guard
      let data = try? JSONEncoder().encode(message),
      data.count <= Self.maximumMessageLength
    else {
      return
    }

    let maximumLength = peripheral.maximumWriteValueLength(
      for: .withResponse
    )
    pendingWriteChunks[peripheral.identifier, default: []].append(
      contentsOf: BluetoothMessageChunk.make(
        data,
        maximumLength: maximumLength
      )
    )
    writeNextChunk(to: peripheral)
  }

  private func writeNextChunk(to peripheral: CBPeripheral) {
    guard
      peripheral.state == .connected,
      !writeInFlightPeripheralIds.contains(peripheral.identifier),
      let characteristic = controlCharacteristics[peripheral.identifier],
      var chunks = pendingWriteChunks[peripheral.identifier],
      !chunks.isEmpty
    else {
      return
    }

    let chunk = chunks.removeFirst()
    pendingWriteChunks[peripheral.identifier] = chunks
    writeInFlightPeripheralIds.insert(peripheral.identifier)
    peripheral.writeValue(
      chunk,
      for: characteristic,
      type: .withResponse
    )
  }

  private func queueNotification(
    _ message: NearbyBluetoothMessage,
    to central: CBCentral
  ) {
    guard
      let data = try? JSONEncoder().encode(message),
      data.count <= Self.maximumMessageLength
    else {
      return
    }

    notificationChunks[central.identifier, default: []].append(
      contentsOf: BluetoothMessageChunk.make(
        data,
        maximumLength: central.maximumUpdateValueLength
      )
    )
    flushNotifications()
  }

  private func flushNotifications() {
    guard let characteristic = localControlCharacteristic else {
      return
    }

    for centralId in Array(notificationChunks.keys) {
      guard
        let central = remoteCentrals[centralId],
        var chunks = notificationChunks[centralId]
      else {
        notificationChunks.removeValue(forKey: centralId)
        continue
      }

      while let chunk = chunks.first {
        guard
          peripheralManager.updateValue(
            chunk,
            for: characteristic,
            onSubscribedCentrals: [central]
          )
        else {
          notificationChunks[centralId] = chunks
          return
        }

        chunks.removeFirst()
      }

      notificationChunks.removeValue(forKey: centralId)
    }
  }

  private func receive(
    _ data: Data,
    from peripheral: CBPeripheral
  ) {
    guard
      let payload = append(
        data,
        to: &incomingPeripheralChunks,
        key: peripheral.identifier
      ),
      let message = decodeAndVerify(payload)
    else {
      return
    }

    completedConnectionIds.insert(peripheral.identifier)
    peerIdsByPeripheralId[peripheral.identifier] = message.peerId
    peripheralsByPeerId[message.peerId] = peripheral
    onPeerSignalStrengthUpdated(
      message.peerId,
      discoveredPeripheralRSSI[peripheral.identifier] ?? Int.min
    )
    onMessageReceived(message)

    if message.kind == .hello {
      peripheral.readRSSI()
      flushPendingMessages(to: peripheral)
    } else if message.kind == .rangeAccept
      || message.kind == .rangeBusy
    {
      finishConnection(peripheral)
    }
  }

  private func receive(
    _ data: Data,
    from central: CBCentral
  ) -> Bool {
    guard
      let payload = append(
        data,
        to: &incomingCentralChunks,
        key: central.identifier
      )
    else {
      return true
    }

    guard let message = decodeAndVerify(payload) else {
      return false
    }

    remoteCentrals[central.identifier] = central
    peerIdsByCentralId[central.identifier] = message.peerId
    onMessageReceived(message)

    if message.kind == .hello,
      let hello = makeMessage(kind: .hello)
    {
      queueNotification(hello, to: central)
    }

    return true
  }

  private func append(
    _ data: Data,
    to accumulators: inout [UUID: BluetoothChunkAccumulator],
    key: UUID
  ) -> Data? {
    guard let chunk = BluetoothMessageChunk(data: data) else {
      accumulators.removeValue(forKey: key)
      return nil
    }

    var accumulator = accumulators[key]

    if accumulator?.messageId != chunk.messageId {
      accumulator = BluetoothChunkAccumulator(
        messageId: chunk.messageId,
        totalCount: chunk.totalCount
      )
    }

    guard var accumulator,
      accumulator.totalCount == chunk.totalCount
    else {
      accumulators.removeValue(forKey: key)
      return nil
    }

    accumulator.chunks[chunk.index] = chunk.payload

    guard accumulator.chunks.count == accumulator.totalCount else {
      accumulators[key] = accumulator
      return nil
    }

    accumulators.removeValue(forKey: key)
    let payload = (0..<accumulator.totalCount).reduce(into: Data()) {
      result, index in
      if let chunk = accumulator.chunks[index] {
        result.append(chunk)
      }
    }

    return payload.count <= Self.maximumMessageLength ? payload : nil
  }

  private func makeMessage(
    kind: NearbyNetworkMessage.Kind,
    discoveryToken: Data? = nil,
    transactionId: UUID? = nil
  ) -> NearbyBluetoothMessage? {
    guard
      !credential.isEmpty,
      !eventScope.isEmpty,
      !localPeerId.isEmpty,
      !transportKey.isEmpty,
      let signingPrivateKey
    else {
      return nil
    }

    let issuedAt = Date().timeIntervalSince1970 * 1_000
    let nonce = UUID().uuidString.lowercased()
    let payload = authenticationPayload(
      kind: kind,
      peerId: localPeerId,
      credential: credential,
      discoveryToken: discoveryToken,
      issuedAt: issuedAt,
      nonce: nonce,
      transactionId: transactionId
    )

    let authenticationCode = HMAC<SHA256>.authenticationCode(
      for: payload,
      using: SymmetricKey(data: Data(transportKey.utf8))
    )
    guard let signature = try? signingPrivateKey.signature(for: payload) else {
      return nil
    }

    return NearbyBluetoothMessage(
      authenticationCode: Data(authenticationCode),
      credential: credential,
      discoveryToken: discoveryToken,
      eventScope: eventScope,
      issuedAt: issuedAt,
      kind: kind,
      nonce: nonce,
      peerId: localPeerId,
      publicKey: signingPrivateKey.publicKey.x963Representation
        .base64EncodedString(),
      signature: signature.derRepresentation,
      transactionId: transactionId
    )
  }

  private func decodeAndVerify(_ data: Data) -> NearbyBluetoothMessage? {
    guard
      let message = try? JSONDecoder().decode(
        NearbyBluetoothMessage.self,
        from: data
      ),
      message.eventScope == eventScope,
      message.peerId != localPeerId,
      UUID(uuidString: message.peerId) != nil,
      !message.credential.isEmpty,
      !message.nonce.isEmpty,
      !message.kind.isRangingControl || message.transactionId != nil,
      abs(Date().timeIntervalSince1970 * 1_000 - message.issuedAt) <= 60_000
    else {
      return nil
    }

    let payload = authenticationPayload(
      kind: message.kind,
      peerId: message.peerId,
      credential: message.credential,
      discoveryToken: message.discoveryToken,
      issuedAt: message.issuedAt,
      nonce: message.nonce,
      transactionId: message.transactionId
    )

    guard
      HMAC<SHA256>.isValidAuthenticationCode(
        message.authenticationCode,
        authenticating: payload,
        using: SymmetricKey(data: Data(transportKey.utf8))
      )
    else {
      return nil
    }

    guard
      let publicKeyData = Data(base64Encoded: message.publicKey),
      let publicKey = try? P256.Signing.PublicKey(
        x963Representation: publicKeyData
      ),
      let signature = try? P256.Signing.ECDSASignature(
        derRepresentation: message.signature
      ),
      publicKey.isValidSignature(signature, for: payload)
    else {
      return nil
    }

    return message
  }

  private func authenticationPayload(
    kind: NearbyNetworkMessage.Kind,
    peerId: String,
    credential: String,
    discoveryToken: Data?,
    issuedAt: Double,
    nonce: String,
    transactionId: UUID?
  ) -> Data {
    Data(
      [
        "areach-bluetooth-control-v2",
        kind.rawValue,
        peerId,
        eventScope,
        credential,
        discoveryToken?.base64EncodedString() ?? "",
        String(format: "%.0f", issuedAt),
        nonce,
        transactionId?.uuidString ?? "",
      ].joined(separator: "\n").utf8
    )
  }

  private func scheduleConnections() {
    guard connectionBatchWorkItem == nil else {
      return
    }

    let workItem = DispatchWorkItem { [weak self] in
      self?.connectionBatchWorkItem = nil
      self?.connectToDiscoveredPeers()
    }
    connectionBatchWorkItem = workItem
    queue.asyncAfter(
      deadline: .now() + Self.discoveryBatchDelay,
      execute: workItem
    )
  }

  private func scheduleConnectionRetry(at deadline: CFTimeInterval) {
    guard isRunning, discoveryIntensity != .backgroundPassive else {
      return
    }

    if let connectionRetryDeadline,
      connectionRetryDeadline <= deadline
    {
      return
    }

    connectionRetryWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else {
        return
      }

      self.connectionRetryWorkItem = nil
      self.connectionRetryDeadline = nil
      self.connectToDiscoveredPeers()
    }
    connectionRetryWorkItem = workItem
    connectionRetryDeadline = deadline
    queue.asyncAfter(
      deadline: .now() + max(0, deadline - CACurrentMediaTime()),
      execute: workItem
    )
  }

  private func cancelConnectionRetry() {
    connectionRetryWorkItem?.cancel()
    connectionRetryWorkItem = nil
    connectionRetryDeadline = nil
  }

  private func scheduleAdvertisementExpiry() {
    let nextExpiry = discoveredPeripherals.compactMap {
      peripheralId,
      peripheral -> CFTimeInterval? in
      guard
        peripheral.state == .disconnected,
        !connectingPeripheralIds.contains(peripheralId),
        let lastAdvertisementAt = lastAdvertisementAt[peripheralId]
      else {
        return nil
      }

      return SpatialBluetoothRetryPolicy.advertisementExpiry(
        lastAdvertisementAt: lastAdvertisementAt,
        staleAfter: SpatialBluetoothTuning.advertisementStaleDuration
      )
    }.min()

    guard let nextExpiry else {
      advertisementExpiryWorkItem?.cancel()
      advertisementExpiryWorkItem = nil
      advertisementExpiryDeadline = nil
      return
    }

    if let advertisementExpiryDeadline,
      advertisementExpiryDeadline <= nextExpiry
    {
      return
    }

    advertisementExpiryWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.expireStaleAdvertisements()
    }
    advertisementExpiryWorkItem = workItem
    advertisementExpiryDeadline = nextExpiry
    queue.asyncAfter(
      deadline: .now() + max(0, nextExpiry - CACurrentMediaTime()),
      execute: workItem
    )
  }

  private func expireStaleAdvertisements() {
    advertisementExpiryWorkItem = nil
    advertisementExpiryDeadline = nil
    guard isRunning else {
      return
    }

    let now = CACurrentMediaTime()
    var didRemovePeripheral = false
    let stalePeripheralIds = discoveredPeripherals.compactMap {
      peripheralId,
      peripheral -> UUID? in
      guard
        peripheral.state == .disconnected,
        !connectingPeripheralIds.contains(peripheralId),
        let lastAdvertisementAt = lastAdvertisementAt[peripheralId],
        now - lastAdvertisementAt >= SpatialBluetoothTuning.advertisementStaleDuration
      else {
        return nil
      }

      return peripheralId
    }

    for peripheralId in stalePeripheralIds {
      guard discoveredPeripherals[peripheralId] != nil else {
        continue
      }

      discoveredPeripherals.removeValue(forKey: peripheralId)
      discoveredPeripheralRSSI.removeValue(forKey: peripheralId)
      smoothedPeripheralRSSI.removeValue(forKey: peripheralId)
      lastAdvertisementAt.removeValue(forKey: peripheralId)
      connectionFailureCount.removeValue(forKey: peripheralId)
      firstDiscoveredAt.removeValue(forKey: peripheralId)

      if let peerId = peerIdsByPeripheralId.removeValue(forKey: peripheralId),
        peripheralsByPeerId[peerId]?.identifier == peripheralId
      {
        peripheralsByPeerId.removeValue(forKey: peerId)
      }
      didRemovePeripheral = true
    }

    if didRemovePeripheral {
      cancelConnectionRetry()
      scheduleConnections()
      SpatialPerformance.signposter.emitEvent(
        "Bluetooth stale attendee removed"
      )
    }

    scheduleAdvertisementExpiry()
  }

  private func scheduleConnectionTimeout(for peripheral: CBPeripheral) {
    connectionTimeouts.removeValue(forKey: peripheral.identifier)?.cancel()

    let workItem = DispatchWorkItem { [weak self, weak peripheral] in
      guard
        let self,
        let peripheral,
        self.connectingPeripheralIds.contains(peripheral.identifier)
      else {
        return
      }

      SpatialPerformance.signposter.emitEvent(
        "Bluetooth wake connection timed out"
      )
      self.finishConnection(peripheral)
    }
    connectionTimeouts[peripheral.identifier] = workItem
    queue.asyncAfter(
      deadline: .now() + Self.connectionTimeout,
      execute: workItem
    )
  }

  private static func eventServiceUUID(eventScope: String) -> CBUUID {
    var bytes = Array(
      SHA256.hash(data: Data("areach-bluetooth-wake:\(eventScope)".utf8))
        .prefix(16)
    )
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    let groups = [
      bytes[0..<4],
      bytes[4..<6],
      bytes[6..<8],
      bytes[8..<10],
      bytes[10..<16],
    ]
    let value =
      groups
      .map { $0.map { String(format: "%02X", $0) }.joined() }
      .joined(separator: "-")

    return CBUUID(string: value)
  }
}

extension NearbyBluetoothWakeService: CBCentralManagerDelegate {
  func centralManager(
    _ central: CBCentralManager,
    willRestoreState dict: [String: Any]
  ) {
    let restoredPeripherals =
      dict[CBCentralManagerRestoredStatePeripheralsKey]
      as? [CBPeripheral] ?? []

    let now = CACurrentMediaTime()
    for peripheral in restoredPeripherals {
      discoveredPeripherals[peripheral.identifier] = peripheral
      lastAdvertisementAt[peripheral.identifier] = now
      firstDiscoveredAt[peripheral.identifier] = now
      peripheral.delegate = self

      if peripheral.state == .connected,
        let serviceUUID
      {
        peripheral.discoverServices([serviceUUID])
      }
    }

    SpatialPerformance.signposter.emitEvent(
      "Bluetooth central state restored",
      "Peripherals: \(restoredPeripherals.count)"
    )
    scheduleConnections()
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    updateScanning()
    scheduleConnections()
    scheduleAdvertisementExpiry()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    guard isRunning else {
      return
    }

    let now = CACurrentMediaTime()
    let isNewDiscovery = discoveredPeripherals[peripheral.identifier] == nil
    discoveredPeripherals[peripheral.identifier] = peripheral
    if isNewDiscovery {
      firstDiscoveredAt[peripheral.identifier] = now
    }

    let rawRSSI = rssi.intValue
    if rawRSSI != 127 {
      let previousRSSI = smoothedPeripheralRSSI[peripheral.identifier]
      let smoothedRSSI = previousRSSI.map {
        $0 * 0.8 + Double(rawRSSI) * 0.2
      } ?? Double(rawRSSI)
      smoothedPeripheralRSSI[peripheral.identifier] = smoothedRSSI
      discoveredPeripheralRSSI[peripheral.identifier] = Int(smoothedRSSI.rounded())
    } else if discoveredPeripheralRSSI[peripheral.identifier] == nil {
      discoveredPeripheralRSSI[peripheral.identifier] = Int.min
    }
    peripheral.delegate = self

    let shouldProcessAdvertisement = isNewDiscovery
      || discoveryIntensity != .cameraAcquisition
      || now - (lastAdvertisementAt[peripheral.identifier] ?? 0)
        >= SpatialBluetoothTuning.duplicateAdvertisementMinimumInterval
    guard shouldProcessAdvertisement else {
      return
    }

    lastAdvertisementAt[peripheral.identifier] = now

    if isNewDiscovery {
      onFirstAdvertisement()
      SpatialPerformance.signposter.emitEvent(
        "Bluetooth attendee discovered",
        "RSSI: \(rawRSSI), first connection eligible: true"
      )
    }

    scheduleConnections()
    scheduleAdvertisementExpiry()
  }

  func centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
  ) {
    guard let serviceUUID else {
      finishConnection(peripheral)
      return
    }

    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    finishConnection(peripheral)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    finishConnection(peripheral)
  }
}

extension NearbyBluetoothWakeService: CBPeripheralDelegate {
  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverServices error: Error?
  ) {
    guard
      error == nil,
      let serviceUUID,
      let service = peripheral.services?.first(where: {
        $0.uuid == serviceUUID
      })
    else {
      finishConnection(peripheral)
      return
    }

    peripheral.discoverCharacteristics(
      [Self.controlCharacteristicUUID, Self.wakeCharacteristicUUID],
      for: service
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard
      error == nil,
      let controlCharacteristic = service.characteristics?.first(where: {
        $0.uuid == Self.controlCharacteristicUUID
      }),
      let wakeCharacteristic = service.characteristics?.first(where: {
        $0.uuid == Self.wakeCharacteristicUUID
      })
    else {
      finishConnection(peripheral)
      return
    }

    controlCharacteristics[peripheral.identifier] = controlCharacteristic
    wakeCharacteristics[peripheral.identifier] = wakeCharacteristic
    peripheral.setNotifyValue(true, for: controlCharacteristic)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard
      error == nil,
      characteristic.uuid == Self.controlCharacteristicUUID,
      characteristic.isNotifying,
      let hello = makeMessage(kind: .hello)
    else {
      finishConnection(peripheral)
      return
    }

    queueWrite(hello, to: peripheral)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard
      error == nil,
      characteristic.uuid == Self.controlCharacteristicUUID,
      let value = characteristic.value
    else {
      finishConnection(peripheral)
      return
    }

    receive(value, from: peripheral)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didReadRSSI rssi: NSNumber,
    error: Error?
  ) {
    guard
      let peerId = peerIdsByPeripheralId[peripheral.identifier],
      let wakeCharacteristic = wakeCharacteristics[peripheral.identifier]
    else {
      finishConnection(peripheral)
      return
    }

    if error == nil, rssi.intValue != 127 {
      onPeerSignalStrengthUpdated(peerId, rssi.intValue)
    }

    peripheral.writeValue(
      Data([1]),
      for: wakeCharacteristic,
      type: .withResponse
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if characteristic.uuid == Self.controlCharacteristicUUID {
      writeInFlightPeripheralIds.remove(peripheral.identifier)

      guard error == nil else {
        finishConnection(peripheral)
        return
      }

      writeNextChunk(to: peripheral)
      return
    }

    guard characteristic.uuid == Self.wakeCharacteristicUUID,
      error == nil
    else {
      finishConnection(peripheral)
      return
    }

    flushPendingMessages(to: peripheral)

    if pendingWriteChunks[peripheral.identifier]?.isEmpty != false,
      !writeInFlightPeripheralIds.contains(peripheral.identifier)
    {
      queue.asyncAfter(deadline: .now() + 0.5) { [weak self, weak peripheral] in
        guard
          let self,
          let peripheral,
          self.pendingWriteChunks[peripheral.identifier]?.isEmpty != false,
          !self.writeInFlightPeripheralIds.contains(peripheral.identifier)
        else {
          return
        }

        self.finishConnection(peripheral)
      }
    }
  }
}

extension NearbyBluetoothWakeService: CBPeripheralManagerDelegate {
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    willRestoreState dict: [String: Any]
  ) {
    let restoredServices =
      dict[CBPeripheralManagerRestoredStateServicesKey]
      as? [CBMutableService] ?? []
    let restoredService = restoredServices.first(where: {
      $0.uuid == serviceUUID
    })
    localControlCharacteristic = restoredService?.characteristics?
      .compactMap { $0 as? CBMutableCharacteristic }
      .first(where: { $0.uuid == Self.controlCharacteristicUUID })
    hasPublishedService = restoredService != nil

    SpatialPerformance.signposter.emitEvent(
      "Bluetooth peripheral state restored",
      "Services: \(restoredServices.count)"
    )
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    publishService()
    scheduleConnections()
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didAdd service: CBService,
    error: Error?
  ) {
    guard
      isRunning,
      error == nil,
      service.uuid == serviceUUID,
      let serviceUUID
    else {
      if error != nil {
        hasPublishedService = false
        localControlCharacteristic = nil
      }
      return
    }

    peripheral.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
    ])
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    var didReceiveWake = false

    for request in requests {
      if request.characteristic.uuid == Self.controlCharacteristicUUID {
        guard request.offset == 0,
          let value = request.value
        else {
          peripheral.respond(to: request, withResult: .invalidOffset)
          continue
        }

        let didAccept = receive(value, from: request.central)
        peripheral.respond(
          to: request,
          withResult: didAccept ? .success : .unlikelyError
        )
        continue
      }

      guard request.characteristic.uuid == Self.wakeCharacteristicUUID else {
        peripheral.respond(to: request, withResult: .requestNotSupported)
        continue
      }

      guard request.offset == 0 else {
        peripheral.respond(to: request, withResult: .invalidOffset)
        continue
      }

      guard request.value == Data([1]) else {
        peripheral.respond(to: request, withResult: .unlikelyError)
        continue
      }

      didReceiveWake = true
      peripheral.respond(to: request, withResult: .success)
    }

    if didReceiveWake {
      SpatialPerformance.signposter.emitEvent(
        "Background attendee awakened"
      )
      onRemoteWakeReceived()
    }
  }

  func peripheralManagerIsReady(
    toUpdateSubscribers peripheral: CBPeripheralManager
  ) {
    flushNotifications()
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    central: CBCentral,
    didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    guard characteristic.uuid == Self.controlCharacteristicUUID else {
      return
    }

    let peerId = peerIdsByCentralId.removeValue(
      forKey: central.identifier
    )
    remoteCentrals.removeValue(forKey: central.identifier)
    incomingCentralChunks.removeValue(forKey: central.identifier)
    notificationChunks.removeValue(forKey: central.identifier)

    if let peerId,
      peerIdsByCentralId.values.contains(peerId) == false,
      peripheralsByPeerId[peerId] == nil
    {
      pendingMessagesByPeerId.removeValue(forKey: peerId)
    }
  }
}

extension NearbyDiscoveryService {
  func handleBluetoothMessage(_ message: NearbyBluetoothMessage) {
    withStateQueue {
      guard
        !expireDiscoveryIfNeeded(),
        let localIdentity,
        message.eventScope == localIdentity.eventScope,
        message.peerId != localPeerId
      else {
        return
      }

      cancelPeerEviction(for: message.peerId)
      bluetoothPeerIds.insert(message.peerId)
      let now = CACurrentMediaTime()
      peerBluetoothLastSeenAt[message.peerId] = now
      markPeerTransportPresence(
        for: message.peerId,
        authenticated: true,
        at: now
      )
      signpostFirstAuthenticatedTransport("bluetooth")

      if !didSignpostFirstTransportDiscovery {
        didSignpostFirstTransportDiscovery = true
        let latencyMilliseconds = discoveryStartedAt.map {
          Int((CACurrentMediaTime() - $0) * 1_000)
        } ?? -1
        SpatialPerformance.signposter.emitEvent(
          "First transport discovery",
          "Latency milliseconds: \(latencyMilliseconds), transport: bluetooth"
        )
      }

      let previousIdentity = peerIdentities[message.peerId]
      peerIdentities[message.peerId] = NearbyPeerIdentity(
        credential: message.credential,
        eventScope: message.eventScope,
        publicKey: message.publicKey,
        userId: previousIdentity?.credential == message.credential
          && previousIdentity?.publicKey == message.publicKey
          ? previousIdentity?.userId
          : nil
      )
      markPeerDiscoveredIfNeeded(message.peerId, reason: "bluetooth-message")

      if previousIdentity?.credential != message.credential {
        peerCredentialLastEmittedAt.removeValue(forKey: message.peerId)
      }
      emitCredentialDiscovered(for: message.peerId)

      switch message.kind {
      case .hello:
        maintainRangingPool()
      case .rangeRequest:
        handleRangingRequest(
          from: message.peerId,
          tokenData: message.discoveryToken,
          transactionId: message.transactionId,
          transportAuthenticated: true
        )
      case .rangeAccept:
        handleRangingAccepted(
          by: message.peerId,
          tokenData: message.discoveryToken,
          transactionId: message.transactionId
        )
      case .rangeBusy:
        handleRangingBusy(
          peerId: message.peerId,
          transactionId: message.transactionId
        )
      case .rangeStop:
        guard let transactionId = message.transactionId else {
          signpostIgnoredRangingMessage(
            kind: .rangeStop,
            peerId: message.peerId,
            transactionId: nil,
            disposition: .missingTransaction
          )
          return
        }
        endRanging(
          with: message.peerId,
          notifyPeer: false,
          reason: "remote-stop",
          transactionId: transactionId
        )
      case .proof:
        break
      }
    }
  }
}

private struct BluetoothChunkAccumulator {
  let messageId: UInt32
  let totalCount: Int
  var chunks: [Int: Data] = [:]
}

private struct BluetoothMessageChunk {
  static let version: UInt8 = 1

  let index: Int
  let messageId: UInt32
  let payload: Data
  let totalCount: Int

  init?(data: Data) {
    let bytes = [UInt8](data)

    guard
      bytes.count >= NearbyBluetoothWakeService.chunkHeaderLength,
      bytes[0] == Self.version
    else {
      return nil
    }

    let messageId =
      UInt32(bytes[1]) << 24
      | UInt32(bytes[2]) << 16
      | UInt32(bytes[3]) << 8
      | UInt32(bytes[4])
    let index = Int(UInt16(bytes[5]) << 8 | UInt16(bytes[6]))
    let totalCount = Int(UInt16(bytes[7]) << 8 | UInt16(bytes[8]))

    guard totalCount > 0, index < totalCount else {
      return nil
    }

    self.index = index
    self.messageId = messageId
    self.payload = Data(
      data.dropFirst(NearbyBluetoothWakeService.chunkHeaderLength)
    )
    self.totalCount = totalCount
  }

  static func make(
    _ payload: Data,
    maximumLength: Int
  ) -> [Data] {
    let payloadLength =
      maximumLength
      - NearbyBluetoothWakeService.chunkHeaderLength

    guard payloadLength > 0 else {
      return []
    }

    let totalCount = max(
      1,
      Int(ceil(Double(payload.count) / Double(payloadLength)))
    )
    guard totalCount <= Int(UInt16.max) else {
      return []
    }

    let messageId = UInt32.random(in: UInt32.min...UInt32.max)

    return (0..<totalCount).map { index in
      let start = index * payloadLength
      let end = min(start + payloadLength, payload.count)
      var chunk = Data([
        version,
        UInt8((messageId >> 24) & 0xFF),
        UInt8((messageId >> 16) & 0xFF),
        UInt8((messageId >> 8) & 0xFF),
        UInt8(messageId & 0xFF),
        UInt8((index >> 8) & 0xFF),
        UInt8(index & 0xFF),
        UInt8((totalCount >> 8) & 0xFF),
        UInt8(totalCount & 0xFF),
      ])
      chunk.append(payload[start..<end])
      return chunk
    }
  }
}
