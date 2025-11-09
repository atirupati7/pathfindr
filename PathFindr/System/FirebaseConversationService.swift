// FirebaseConversationService.swift
// Manages conversation history storage and retrieval using Firebase Firestore
import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

struct ConversationExchange {
    let userPrompt: String
    let assistantResponse: String
    let imageData: Data? // Base64 encoded image data (JPEG)
    let timestamp: Date
}

protocol ConversationService {
    func saveExchange(userPrompt: String, assistantResponse: String, imageData: Data?) async
    func getRecentExchanges(limit: Int) async -> [ConversationExchange]
    func clearHistory() async
}

// Firebase implementation
final class FirebaseConversationService: ConversationService {
    private let db: Firestore
    private let collectionName = "conversations"
    private let userId: String
    
    init(userId: String = "default_user") {
        self.userId = userId
        // Firebase should be initialized in MainApp.init() before Navigator is created
        // Firestore.firestore() will work if FirebaseApp.configure() has been called
        self.db = Firestore.firestore()
        print("[FirebaseConversationService] Initialized for user: \(userId)")
    }
    
    func saveExchange(userPrompt: String, assistantResponse: String, imageData: Data?) async {
        let exchange = ConversationExchange(
            userPrompt: userPrompt,
            assistantResponse: assistantResponse,
            imageData: imageData,
            timestamp: Date()
        )
        
        do {
            var documentData: [String: Any] = [
                "userPrompt": exchange.userPrompt,
                "assistantResponse": exchange.assistantResponse,
                "timestamp": Timestamp(date: exchange.timestamp)
            ]
            
            // Store image as base64 string if available
            if let imageData = exchange.imageData {
                let imageBase64 = imageData.base64EncodedString()
                documentData["imageData"] = imageBase64
                print("[Firebase] Saving exchange with image (size: \(imageData.count) bytes, base64: \(imageBase64.count) chars)")
            } else {
                print("[Firebase] Saving exchange without image")
            }
            
            try await db.collection(collectionName)
                .document(userId)
                .collection("exchanges")
                .addDocument(data: documentData)
            print("[Firebase] Saved conversation exchange for user: \(userId)")
        } catch {
            print("[Firebase] Error saving exchange: \(error.localizedDescription)")
            // Fallback: log the error but don't crash
        }
    }
    
    func getRecentExchanges(limit: Int) async -> [ConversationExchange] {
        do {
            let snapshot = try await db.collection(collectionName)
                .document(userId)
                .collection("exchanges")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            let exchanges = snapshot.documents.compactMap { doc -> ConversationExchange? in
                let data = doc.data()
                guard let userPrompt = data["userPrompt"] as? String,
                      let assistantResponse = data["assistantResponse"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp else {
                    print("[Firebase] Warning: Failed to parse exchange document: \(doc.documentID)")
                    return nil
                }
                
                // Decode image data if present
                var imageData: Data? = nil
                if let imageBase64 = data["imageData"] as? String {
                    imageData = Data(base64Encoded: imageBase64)
                    if imageData == nil {
                        print("[Firebase] Warning: Failed to decode image data for document: \(doc.documentID)")
                    }
                }
                
                return ConversationExchange(
                    userPrompt: userPrompt,
                    assistantResponse: assistantResponse,
                    imageData: imageData,
                    timestamp: timestamp.dateValue()
                )
            }
            
            print("[Firebase] Retrieved \(exchanges.count) exchanges for user: \(userId)")
            // Return in chronological order (oldest first)
            return exchanges.reversed()
        } catch {
            print("[Firebase] Error fetching exchanges: \(error.localizedDescription)")
            // Return empty array on error - app will work without history
            return []
        }
    }
    
    func clearHistory() async {
        do {
            let snapshot = try await db.collection(collectionName)
                .document(userId)
                .collection("exchanges")
                .getDocuments()
            
            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
            print("[Firebase] Cleared \(snapshot.documents.count) conversation exchanges for user: \(userId)")
        } catch {
            print("[Firebase] Error clearing history: \(error.localizedDescription)")
        }
    }
}

// Mock implementation for development (works without Firebase)
final class MockConversationService: ConversationService {
    private var exchanges: [ConversationExchange] = []
    private let maxExchanges = 10
    
    func saveExchange(userPrompt: String, assistantResponse: String, imageData: Data?) async {
        let exchange = ConversationExchange(
            userPrompt: userPrompt,
            assistantResponse: assistantResponse,
            imageData: imageData,
            timestamp: Date()
        )
        exchanges.append(exchange)
        
        // Keep only recent exchanges
        if exchanges.count > maxExchanges {
            exchanges.removeFirst(exchanges.count - maxExchanges)
        }
        
        if imageData != nil {
            print("[MockConversationService] Saved exchange with image (total: \(exchanges.count))")
        } else {
            print("[MockConversationService] Saved exchange without image (total: \(exchanges.count))")
        }
    }
    
    func getRecentExchanges(limit: Int) async -> [ConversationExchange] {
        let count = min(limit, exchanges.count)
        return Array(exchanges.suffix(count))
    }
    
    func clearHistory() async {
        exchanges.removeAll()
        print("[MockConversationService] Cleared history")
    }
}

