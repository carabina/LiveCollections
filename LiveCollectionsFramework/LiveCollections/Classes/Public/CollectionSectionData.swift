//
//  CollectionSectionData.swift
//  LiveCollections
//
//  Created by Stephane Magne on 10/15/17.
//  Copyright © 2017 Scribd. All rights reserved.
//

import Foundation

/**
 This is a tool for the scenario:
 A collection/table view that has multiple sections where data items are unique across all sections.
 (e.g. a data item in section 0 will not also appear in section 3)
 
 Due to the timing nature of animations, a view must be set on this object and all animations will
 be performed automatically.

 Much like the use of CollectionData, you only need to call `update` or `append`. However to use
 this class, you will need to create a section based data structure that adheres to
 `UniquelyIdentifiableSection`.
 */

public final class CollectionSectionData<SectionType: UniquelyIdentifiableSection>: CollectionSectionDataActionsInterface, SectionDataProvider, SectionCalculatingDataProvider {
    
    public typealias DataType = SectionType.DataType
    
    // table or collection view
    private let view: SectionDeltaUpdatableView
    
    // delegate
    public weak var reloadDelegate: CollectionSectionDataManualReloadDelegate?
    private var deletionNotificationDelegate: AnyCollectionDataDeletionNotificationDelegate<DataType>?
    
    // section data
    private var _sections: [SectionType]
    internal(set) public var sections: [SectionType] {
        get { return dataQueue.sync { _sections } }
        set { dataQueue.async(flags: .barrier) { self._sections = newValue } }
    }

    private var _calculatingSections: [SectionType]?
    internal(set) public var calculatingSections: [SectionType]? {
        get { return dataQueue.sync { _calculatingSections } }
        set {
            dataQueue.async(flags: .barrier) {
                guard self._calculatingSections == nil || newValue == nil else { return }
                self._calculatingSections = newValue
            }
        }
    }
    
    // item data
    private var _items: [DataType]
    internal(set) public var items: [DataType] {
        get { return dataQueue.sync { _items } }
        set { dataQueue.async(flags: .barrier) { self._items = newValue } }
    }

    func orderedItems(for sections: [SectionType]) -> [DataType] {
        return CollectionSectionData.orderedItems(for: sections)
    }

    private static func orderedItems(for sections: [SectionType]) -> [DataType] {
       return sections.flatMap { $0.items }
    }
    
    // calculator
    private let dataCalculator = SectionDataCalculator<SectionType>()
    
    // animation threshold
    public var dataCountAnimationThreshold: Int = 10000
    
    // thread safety
    private let dataQueue = DispatchQueue(label: "\(CollectionSectionData.self) dispatch queue", attributes: .concurrent)
    private let calculationQueue = DispatchQueue.main
        //DispatchQueue(label: "\(CollectionSectionData.self) calculation dispatch queue")

    public init(view: SectionDeltaUpdatableView, sectionData: [SectionType] = []) {
        self.view = view
        self._sections = sectionData
        self._items = CollectionSectionData.orderedItems(for: sectionData)
    }
    
    public func setDeletionNotificationDelegate<Delegate: CollectionDataDeletionNotificationDelegate>(_ delegate: Delegate) where Delegate.DataType == DataType {
        self.deletionNotificationDelegate = AnyCollectionDataDeletionNotificationDelegate(delegate)
    }
    
    // MARK: CollectionSectionDataStateInterface
    
    public var sectionCount: Int {
        return sections.count
    }
    
    public var isEmpty: Bool {
        return sections.isEmpty
    }
    
    public var isCalculating: Bool {
        guard let calculatingSections = calculatingSections else { return false }
        return calculatingSections.isEmpty == false
    }
    
    public func itemCount(forSection section: Int) -> Int {
        return sections[section].items.count
    }

    public subscript(index: Int) -> SectionType {
        return sections[index]
    }
    
    public subscript(section: Int, item: Int) -> DataType {
        return sections[section].items[item]
    }
    
    public subscript(indexPath: IndexPath) -> DataType {
        return self[indexPath.section, indexPath.item]
    }

    // MARK: CollectionSectionDataActionsInterface
    
    public func update(_ updatedData: [SectionType], completion: (() -> Void)? = nil) {
        let shouldAppend: Bool = {
            guard let calculatingSections = calculatingSections else { return isEmpty }
            return calculatingSections.isEmpty
        }()
        
        guard shouldAppend == false else {
            append(updatedData, completion: completion)
            return
        }

        calculatingSections = updatedData
        calculationQueue.async {
            self.dataCalculator.updateAndAnimate(updatedData,
                                                 sectionProvider: self,
                                                 view: self.view,
                                                 reloadDelegate: self.reloadDelegate,
                                                 deletionDelegate: self.deletionNotificationDelegate,
                                                 completion: completion)
        }
    }
    
    public func append(_ appendedItems: [SectionType], completion: (() -> Void)? = nil) {
        calculatingSections = appendedItems
        calculationQueue.async {
            self.dataCalculator.appendAndAnimate(appendedItems,
                                                 sectionProvider: self,
                                                 view: self.view,
                                                 reloadDelegate: self.reloadDelegate,
                                                 completion: completion)
        }
    }
}

// MARK: - Non-unique Data

public typealias NonUniqueCollectionSectionData<NonUniqueSection: UniquelyIdentifiableSection> = CollectionSectionData<NonUniqueSectionDatum<NonUniqueSection>> where NonUniqueSection.DataType: NonUniquelyIdentifiable

public extension NonUniqueCollectionSectionData {

    public convenience init<NonUniqueSection>(view: SectionDeltaUpdatableView, sectionData: [NonUniqueSection] = []) where SectionType == NonUniqueSectionDatum<NonUniqueSection> {
        let updatedUniqueData = NonUniqueCollectionSectionData._transformData(sectionData)
        self.init(view: view, sectionData: updatedUniqueData)
    }
    
    public func update<NonUniqueSection>(_ nonUniqueData: [NonUniqueSection], completion: (() -> Void)? = nil) where SectionType == NonUniqueSectionDatum<NonUniqueSection> {
        let updatedUniqueData = NonUniqueCollectionSectionData._transformData(nonUniqueData)
        self.update(updatedUniqueData, completion: completion)
    }

    public func append<NonUniqueSection>(_ nonUniqueData: [NonUniqueSection], completion: (() -> Void)? = nil) where SectionType == NonUniqueSectionDatum<NonUniqueSection> {
            let updatedUniqueData = NonUniqueCollectionSectionData._transformData(nonUniqueData)
            self.append(updatedUniqueData, completion: completion)
    }
    
    private static func _transformData<NonUniqueSection>(_ nonUniqueData: [NonUniqueSection]) -> [NonUniqueSectionDatum<NonUniqueSection>] where SectionType == NonUniqueSectionDatum<NonUniqueSection> {
        let dataFactory = NonUniqueDataFactory<NonUniqueSection.DataType>(automaticallyClearsData: false)
        return nonUniqueData.map { NonUniqueSectionDatum<NonUniqueSection>(sectionData: $0, dataFactory: dataFactory) }
    }
}
