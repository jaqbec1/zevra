import CoreData
import Foundation

@MainActor
public final class ObservationStore {
  public let container: NSPersistentCloudKitContainer

  public init(url: URL?, cloudContainer: String? = nil) throws {
    container = NSPersistentCloudKitContainer(
      name: "AttentionLog", managedObjectModel: Self.model())
    let description = NSPersistentStoreDescription()
    description.shouldAddStoreAsynchronously = false
    if let url {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      description.url = url
      description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
      description.setOption(
        true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    } else {
      description.type = NSInMemoryStoreType
    }
    if let cloudContainer, url != nil {
      description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
        containerIdentifier: cloudContainer)
    }
    container.persistentStoreDescriptions = [description]
    var failure: Error?
    container.loadPersistentStores { _, error in failure = error }
    if let failure { throw failure }
    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy(
      merge: .mergeByPropertyObjectTrumpMergePolicyType)
    container.viewContext.transactionAuthor = "AttentionLog"
  }

  public func save(_ observation: Observation) throws {
    guard observation.activeSeconds.isFinite, observation.activeSeconds > 0 else { return }
    let context = container.viewContext
    let request = NSFetchRequest<NSManagedObject>(entityName: "Observation")
    request.predicate = NSPredicate(format: "id == %@", observation.id as NSUUID)
    request.fetchLimit = 1
    let object =
      try context.fetch(request).first
      ?? NSEntityDescription.insertNewObject(forEntityName: "Observation", into: context)
    let previous = object.value(forKey: "activeSeconds") as? Double ?? 0
    guard observation.activeSeconds >= previous else { return }
    object.setValue(observation.id, forKey: "id")
    object.setValue(observation.deviceID, forKey: "deviceID")
    object.setValue(observation.url, forKey: "url")
    object.setValue(String(observation.title.prefix(512)), forKey: "title")
    object.setValue(observation.startedAt, forKey: "startedAt")
    object.setValue(observation.lastSeenAt, forKey: "lastSeenAt")
    object.setValue(observation.activeSeconds, forKey: "activeSeconds")
    do { try context.save() } catch {
      context.rollback()
      throw error
    }
  }

  public func recent(
    limit: Int = 100, search: String = "", policy: CapturePolicy? = nil
  ) throws -> [Observation] {
    guard limit > 0 else { return [] }
    let context = container.viewContext
    // All local writes are saved immediately, so imported changes can safely refresh this context.
    context.refreshAllObjects()
    let request = NSFetchRequest<NSManagedObject>(entityName: "Observation")
    request.sortDescriptors = [
      NSSortDescriptor(key: "lastSeenAt", ascending: false),
      NSSortDescriptor(key: "id", ascending: true),
    ]
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      request.predicate = NSPredicate(
        format: "title CONTAINS[cd] %@ OR url CONTAINS[cd] %@", query, query)
    }
    // Apply URL rules before the visible limit, including when an entire batch is excluded.
    request.fetchLimit = 200
    var observations: [Observation] = []
    while observations.count < limit {
      let batch = try context.fetch(request)
      for object in batch {
        guard let id = object.value(forKey: "id") as? UUID,
          let deviceID = object.value(forKey: "deviceID") as? String,
          let url = object.value(forKey: "url") as? String,
          let started = object.value(forKey: "startedAt") as? Date,
          let last = object.value(forKey: "lastSeenAt") as? Date,
          policy == nil || policy?.acceptedURL(url) != nil
        else { continue }
        observations.append(
          Observation(
            id: id, deviceID: deviceID, url: url,
            title: object.value(forKey: "title") as? String ?? "",
            startedAt: started, lastSeenAt: last,
            activeSeconds: object.value(forKey: "activeSeconds") as? Double ?? 0))
        if observations.count == limit { break }
      }
      if batch.count < request.fetchLimit { break }
      request.fetchOffset += batch.count
    }
    return observations
  }

  public func activeSeconds(for url: String) throws -> Double {
    let request = NSFetchRequest<NSManagedObject>(entityName: "Observation")
    request.predicate = NSPredicate(format: "url == %@", url)
    request.propertiesToFetch = ["activeSeconds"]
    return try container.viewContext.fetch(request).reduce(0) {
      $0 + ($1.value(forKey: "activeSeconds") as? Double ?? 0)
    }
  }

  public func close() throws {
    container.viewContext.reset()
    for store in container.persistentStoreCoordinator.persistentStores {
      try container.persistentStoreCoordinator.remove(store)
    }
  }

  private static func model() -> NSManagedObjectModel {
    let model = NSManagedObjectModel()
    let entity = NSEntityDescription()
    entity.name = "Observation"
    entity.managedObjectClassName = "NSManagedObject"
    let fields: [(String, NSAttributeType)] = [
      ("id", .UUIDAttributeType), ("deviceID", .stringAttributeType),
      ("url", .stringAttributeType), ("title", .stringAttributeType),
      ("startedAt", .dateAttributeType), ("lastSeenAt", .dateAttributeType),
      ("activeSeconds", .doubleAttributeType),
    ]
    entity.properties = fields.map { name, type in
      let attribute = NSAttributeDescription()
      attribute.name = name
      attribute.attributeType = type
      attribute.isOptional = true  // CloudKit schema requirement; validated when decoding.
      return attribute
    }
    model.entities = [entity]
    return model
  }
}
