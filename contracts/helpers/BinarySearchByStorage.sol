// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math2 {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
    }
}

library Arrays2 {
    /**
     * @dev Searches a sorted `array` and returns the first index that contains
     * a value greater or equal to `element`. If no such index exists (i.e. all
     * values in the array are strictly less than `element`), the array length is
     * returned. Time complexity O(log n).
     *
     * `array` is expected to be sorted in ascending order, and to contain no
     * repeated elements.
     */
    function findUpperBound(
        uint256[] storage array,
        uint256 element,
        uint256 low
    ) internal view returns (uint256) {
        if (array.length == 0) {
            return (0);
        }

        uint256 high = array.length;

        while (low < high) {
            uint256 mid = Math2.average(low, high);

            if (array[mid] > element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return (low);
    }
}
