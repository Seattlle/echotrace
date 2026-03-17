package errors

import (
	"errors"
	"fmt"
)

var (
	ErrAlreadyDecrypted              = errors.New("database file is already decrypted")
	ErrDecryptHashVerificationFailed = errors.New("hash verification failed during decryption")
	ErrDecryptIncorrectKey           = errors.New("incorrect decryption key")
	ErrDecryptOperationCanceled      = errors.New("decryption operation was canceled")
)

func OpenFileFailed(path string, cause error) error {
	return fmt.Errorf("failed to open file %s: %w", path, cause)
}

func StatFileFailed(path string, cause error) error {
	return fmt.Errorf("failed to stat file %s: %w", path, cause)
}

func ReadFileFailed(path string, cause error) error {
	return fmt.Errorf("failed to read file %s: %w", path, cause)
}

func IncompleteRead(cause error) error {
	return fmt.Errorf("incomplete header read during decryption: %w", cause)
}

func WriteOutputFailed(cause error) error {
	return fmt.Errorf("failed to write output: %w", cause)
}

func DecodeKeyFailed(cause error) error {
	return fmt.Errorf("failed to decode hex key: %w", cause)
}

func DecryptCreateCipherFailed(cause error) error {
	return fmt.Errorf("failed to create cipher: %w", cause)
}

func PlatformUnsupported(platform string, version int) error {
	return fmt.Errorf("unsupported platform: %s v%d", platform, version)
}
