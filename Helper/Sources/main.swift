// Adapted from Awayke@b502251: AwaykeHelper/main.swift
//
//  main.swift
//  MooringHelper
//
//  Entry point of the privileged launchd daemon (dev.mooring.helper).
//

import Foundation

let requirement = ClientRequirement.load(from: Bundle.main.infoDictionary)
let service = HelperService(clientRequirement: requirement)
let listener = NSXPCListener(machServiceName: MooringHelperConstants.machServiceName)
if let requirement {
    // Enforced by the system from the connecting process's audit token (macOS 13+).
    listener.setConnectionCodeSigningRequirement(requirement)
}
listener.delegate = service
listener.resume()
dispatchMain()
