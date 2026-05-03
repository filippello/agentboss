import AppKit

/// Imports a pet from petdex.crafter.run and converts the single
/// `spritesheet.webp` (1536×1872, 9 rows × 8 cols, 192×208 frames) into
/// the per-animation horizontal PNGs FocusPal expects, written to
/// `~/.focuspal/characters/<slug>/`.
///
/// Layout from the Codex Pets spec (every petdex pet follows this):
///   row 0: Idle (≤6 frames)
///   row 1: Run Right (≤8 frames)
///   row 2: Run Left (mirrored — we ignore, FocusPal mirrors itself)
///   row 3: Waving
///   row 4: Jumping
///   row 5: Failed
///   row 6: Waiting
///   row 7: Running
///   row 8: Review
///
/// FocusPal needs 7 anim sheets per character. Mapping:
///   Idle.png        ← row 0
///   Run.png         ← row 1
///   Jump.png        ← row 4 (Jumping)
///   Fall.png        ← row 4 (same data)
///   Hit.png         ← row 5 (Failed)
///   Double Jump.png ← row 1 (fallback to Run)
///   Wall Jump.png   ← row 1 (fallback to Run)
///
/// All output frames are 96×96 to match the character window. The source
/// 192×208 frames are scaled with aspect-fit + transparent padding.
final class PetdexImporter {

    /// Result reported back to the caller.
    enum ImportError: Error, CustomStringConvertible {
        case invalidName
        case manifestUnreachable
        case slugNotFound(String)
        case spritesheetTooLarge
        case spritesheetWrongMagic
        case spritesheetDecodeFailed
        case writeFailed(String)
        case other(String)

        var description: String {
            switch self {
            case .invalidName: return "Pet name must be 1-32 chars, alphanumeric/underscore/dash."
            case .manifestUnreachable: return "Couldn't fetch petdex /api/manifest."
            case .slugNotFound(let s): return "Pet '\(s)' not found in petdex manifest."
            case .spritesheetTooLarge: return "Spritesheet over 5MB — refusing to download."
            case .spritesheetWrongMagic: return "Downloaded file isn't a WebP image."
            case .spritesheetDecodeFailed: return "Couldn't decode the WebP spritesheet."
            case .writeFailed(let path): return "Couldn't write to \(path)."
            case .other(let msg): return msg
            }
        }
    }

    static let manifestURL = URL(string: "https://petdex.crafter.run/api/manifest")!

    /// Async entry point. Resolves on the main queue with the character
    /// directory on success, or an `ImportError`.
    static func importPet(name rawName: String,
                          completion: @escaping (Result<String, ImportError>) -> Void) {
        // 1) Validate the name BEFORE any network I/O.
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 32,
              trimmed.range(of: #"^[a-zA-Z0-9_-]{1,32}$"#, options: .regularExpression) != nil
        else {
            DispatchQueue.main.async { completion(.failure(.invalidName)) }
            return
        }
        let slug = trimmed.lowercased()

        // 2) Fetch the manifest (defines the canonical URLs we trust).
        var manifestRequest = URLRequest(url: manifestURL)
        manifestRequest.timeoutInterval = 10
        URLSession.shared.dataTask(with: manifestRequest) { data, _, error in
            guard error == nil, let data = data else {
                DispatchQueue.main.async { completion(.failure(.manifestUnreachable)) }
                return
            }
            guard let pet = findPet(slug: slug, in: data) else {
                DispatchQueue.main.async { completion(.failure(.slugNotFound(slug))) }
                return
            }
            // 3) Download the spritesheet. URL comes from the manifest, so
            //    petdex itself decides the host.
            downloadSpritesheet(url: pet.spritesheetURL) { result in
                switch result {
                case .failure(let err):
                    DispatchQueue.main.async { completion(.failure(err)) }
                case .success(let webp):
                    // 4) Decode + slice + write.
                    do {
                        let dir = try sliceAndWrite(webp: webp, slug: slug)
                        DispatchQueue.main.async { completion(.success(dir)) }
                    } catch let err as ImportError {
                        DispatchQueue.main.async { completion(.failure(err)) }
                    } catch {
                        DispatchQueue.main.async { completion(.failure(.other(String(describing: error)))) }
                    }
                }
            }
        }.resume()
    }

    // MARK: - Manifest lookup

    private struct ManifestPet {
        let slug: String
        let displayName: String
        let spritesheetURL: URL
    }

    private static func findPet(slug: String, in data: Data) -> ManifestPet? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pets = json["pets"] as? [[String: Any]]
        else { return nil }

        for pet in pets {
            guard let s = pet["slug"] as? String, s.lowercased() == slug else { continue }
            guard let urlStr = pet["spritesheetUrl"] as? String,
                  let url = URL(string: urlStr) else { return nil }
            let display = (pet["displayName"] as? String) ?? slug
            return ManifestPet(slug: s, displayName: display, spritesheetURL: url)
        }
        return nil
    }

    // MARK: - Spritesheet download

    private static let maxSpritesheetBytes: Int = 5 * 1024 * 1024     // 5MB

    private static func downloadSpritesheet(url: URL,
                                            completion: @escaping (Result<Data, ImportError>) -> Void) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { data, response, error in
            guard error == nil, let data = data else {
                completion(.failure(.spritesheetWrongMagic))
                return
            }
            // Size check
            if data.count > maxSpritesheetBytes {
                completion(.failure(.spritesheetTooLarge))
                return
            }
            // Magic byte check: RIFF........WEBP
            guard data.count >= 12 else { completion(.failure(.spritesheetWrongMagic)); return }
            let riff = [UInt8](data[0..<4])
            let webp = [UInt8](data[8..<12])
            guard riff == [0x52, 0x49, 0x46, 0x46], webp == [0x57, 0x45, 0x42, 0x50] else {
                completion(.failure(.spritesheetWrongMagic))
                return
            }
            // Content-type sanity (best effort — UploadThing CDN is honest).
            if let http = response as? HTTPURLResponse,
               let ct = http.value(forHTTPHeaderField: "Content-Type"),
               !ct.lowercased().hasPrefix("image/webp") {
                completion(.failure(.spritesheetWrongMagic))
                return
            }
            completion(.success(data))
        }.resume()
    }

    // MARK: - Slice + write

    /// Standard Codex Pets layout. Frame counts per row (any trailing empty
    /// frames are harmless — we render only the count we ask for).
    private struct SourceLayout {
        static let cols = 8
        static let rows = 9
        static let sheetWidth: CGFloat = 1536
        static let sheetHeight: CGFloat = 1872
        static var frameW: CGFloat { sheetWidth / CGFloat(cols) }      // 192
        static var frameH: CGFloat { sheetHeight / CGFloat(rows) }     // 208
    }

    /// FocusPal anim → (source row, frame count to copy)
    private struct AnimSpec {
        let filename: String
        let sourceRow: Int
        let frameCount: Int
        let loops: Bool
    }

    private static let outputAnims: [AnimSpec] = [
        AnimSpec(filename: "Idle (32x32).png",        sourceRow: 0, frameCount: 6, loops: true),
        AnimSpec(filename: "Run (32x32).png",         sourceRow: 1, frameCount: 8, loops: true),
        AnimSpec(filename: "Jump (32x32).png",        sourceRow: 4, frameCount: 1, loops: false),
        AnimSpec(filename: "Fall (32x32).png",        sourceRow: 4, frameCount: 1, loops: false),
        AnimSpec(filename: "Hit (32x32).png",         sourceRow: 5, frameCount: 6, loops: false),
        AnimSpec(filename: "Double Jump (32x32).png", sourceRow: 1, frameCount: 6, loops: false),
        AnimSpec(filename: "Wall Jump (32x32).png",   sourceRow: 1, frameCount: 5, loops: false),
    ]

    /// Output frames are square 96×96 (matches the character window).
    private static let outFrameSize: CGFloat = 96

    private static func sliceAndWrite(webp: Data, slug: String) throws -> String {
        guard let source = NSImage(data: webp) else {
            throw ImportError.spritesheetDecodeFailed
        }
        // Make sure dimensions match what we expect — petdex pets are
        // standardised at 1536×1872. Off-spec sheets get rejected.
        let s = source.size
        guard abs(s.width - SourceLayout.sheetWidth) < 4,
              abs(s.height - SourceLayout.sheetHeight) < 4
        else {
            throw ImportError.other("Spritesheet has unexpected dimensions: \(Int(s.width))×\(Int(s.height))")
        }

        let home = NSHomeDirectory()
        let charDir = "\(home)/.focuspal/characters/\(slug)"
        try? FileManager.default.removeItem(atPath: charDir)        // start clean
        do {
            try FileManager.default.createDirectory(
                atPath: charDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ImportError.writeFailed(charDir)
        }

        do {
            for anim in outputAnims {
                let png = try buildAnimSheet(source: source, spec: anim)
                let path = "\(charDir)/\(anim.filename)"
                guard (try? png.write(to: URL(fileURLWithPath: path))) != nil else {
                    throw ImportError.writeFailed(path)
                }
            }
        } catch {
            // Cleanup partial dir on any failure.
            try? FileManager.default.removeItem(atPath: charDir)
            throw error
        }

        return charDir
    }

    /// Build a single output PNG: `frameCount × outFrameSize` wide, `outFrameSize` tall.
    /// Each output frame is the corresponding source frame scaled-to-fit
    /// inside a square (preserving aspect; transparent letterbox if needed).
    private static func buildAnimSheet(source: NSImage, spec: AnimSpec) throws -> Data {
        let outW = CGFloat(spec.frameCount) * outFrameSize
        let outSize = NSSize(width: outW, height: outFrameSize)
        let out = NSImage(size: outSize)
        out.lockFocus()
        NSGraphicsContext.current?.cgContext.clear(
            CGRect(x: 0, y: 0, width: outW, height: outFrameSize)
        )
        // Source uses top-left origin convention in the layout description.
        // NSImage drawing uses bottom-left, so we flip the row index when
        // computing the source rect.
        let srcRowFromBottom = SourceLayout.rows - 1 - spec.sourceRow
        let srcY = CGFloat(srcRowFromBottom) * SourceLayout.frameH

        for i in 0..<spec.frameCount {
            let srcX = CGFloat(i) * SourceLayout.frameW
            let srcRect = NSRect(x: srcX, y: srcY,
                                 width: SourceLayout.frameW,
                                 height: SourceLayout.frameH)

            // Scale-to-fit inside a square, transparent letterbox.
            let scale = min(outFrameSize / SourceLayout.frameW,
                            outFrameSize / SourceLayout.frameH)
            let drawW = SourceLayout.frameW * scale
            let drawH = SourceLayout.frameH * scale
            let dstRect = NSRect(
                x: CGFloat(i) * outFrameSize + (outFrameSize - drawW) / 2,
                y: (outFrameSize - drawH) / 2,
                width: drawW,
                height: drawH
            )
            source.draw(in: dstRect, from: srcRect, operation: .copy, fraction: 1.0)
        }
        out.unlockFocus()

        // PNG-encode
        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw ImportError.other("PNG encoding failed for \(spec.filename)")
        }
        return png
    }
}
