package auth

import "testing"

// CATATAN PEMELIHARAAN: tes ini menjaga verifikasi password benar/salah setelah
// perubahan format Argon2id atau parameter hashing.
func TestHashPasswordAndVerify(t *testing.T) {
	password := "kata-sandi-rahasia-yang-kuat"
	encoded, err := HashPassword(password)
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword(encoded, password) {
		t.Fatal("hash harus menerima kata sandi yang benar")
	}
	if VerifyPassword(encoded, "kata-sandi-yang-salah") {
		t.Fatal("hash tidak boleh menerima kata sandi yang salah")
	}
}

// CATATAN PEMELIHARAAN: hash dari sumber yang tidak dipercaya tidak boleh
// memaksa alokasi memori besar sebelum parameter dibatasi.
func TestVerifyPasswordRejectsUnsafeParameters(t *testing.T) {
	encoded := "$argon2id$v=19$m=999999999,t=3,p=1$MTIzNDU2Nzg$MTIzNDU2Nzg5MDEyMzQ1Ng"
	if VerifyPassword(encoded, "kata-sandi") {
		t.Fatal("hash dengan parameter memori berlebihan harus ditolak")
	}
}
