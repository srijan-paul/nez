pub const NESError = error{
    NotImplemented,
    InvalidROM,
    UnsupportedMapper,
};

/// A bank register (PRG or CHR) has 5 bits.
/// Meaning one could theoretically access bank number 31 (0b11111) in a cart that only has
/// one or two banks. To prevent this, we mask away the high bits when the bank number is too large.
/// The mask to use depends on the number of banks present in the cart.
/// If there are 9 banks in the cart, but the programmer tries to access bank #31,
/// we do 0b11111 & 0b00111 = 0b00111, which is a valid bank number less than 9.
pub fn bankingMask(bank_count: u8) u5 {
    return switch (bank_count) {
        0...1 => 1,
        2...7 => 3,
        8...127 => 7,
        128...255 => 15,
    };
}
