import CStbVorbis

// STBVorbisError
public struct StbVorbisError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    /// The STBVorbisError, which `message` names.
    public let code: Int32
    public let message: String

    public var description: String {
        "\(operation) failed: \(message)"
    }

    init(operation: String, code: Int32) {
        self.operation = operation
        self.code = code
        message = Self.name(of: code)
    }

    private static func name(of code: Int32) -> String {
        switch STBVorbisError(UInt32(bitPattern: code)) {
        case VORBIS__no_error: "no error"
        case VORBIS_need_more_data: "need more data"
        case VORBIS_invalid_api_mixing: "invalid API mixing"
        case VORBIS_outofmem: "out of memory"
        case VORBIS_feature_not_supported: "feature not supported"
        case VORBIS_too_many_channels: "too many channels"
        case VORBIS_file_open_failure: "file open failure"
        case VORBIS_seek_without_length: "seek without length"
        case VORBIS_unexpected_eof: "unexpected end of file"
        case VORBIS_seek_invalid: "invalid seek"
        case VORBIS_invalid_setup: "invalid setup"
        case VORBIS_invalid_stream: "invalid stream"
        case VORBIS_missing_capture_pattern: "missing capture pattern"
        case VORBIS_invalid_stream_structure_version: "invalid stream structure version"
        case VORBIS_continued_packet_flag_invalid: "invalid continued packet flag"
        case VORBIS_incorrect_stream_serial_number: "incorrect stream serial number"
        case VORBIS_invalid_first_page: "invalid first page"
        case VORBIS_bad_packet_type: "bad packet type"
        case VORBIS_cant_find_last_page: "can't find last page"
        case VORBIS_seek_failed: "seek failed"
        case VORBIS_ogg_skeleton_not_supported: "Ogg skeleton not supported"
        default: "error \(code)"
        }
    }
}
