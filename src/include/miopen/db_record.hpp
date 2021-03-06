/*******************************************************************************
 *
 * MIT License
 *
 * Copyright (c) 2017 Advanced Micro Devices, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 *******************************************************************************/
#ifndef GUARD_MIOPEN_DB_RECORD_HPP_
#define GUARD_MIOPEN_DB_RECORD_HPP_

#include <miopen/config.h>

#include <miopen/logger.hpp>

#include <cassert>
#include <sstream>
#include <string>
#include <unordered_map>

namespace miopen {

/// db consists of 0 or more records.
/// Each record is an ASCII text line.
/// Record format:
///   [ KEY "=" ID ":" VALUES { ";" ID ":" VALUES} ]
///
/// KEY - An identifer of a record.
/// ID - Can be considered as a sub-key under which respective VALUES are stored.
/// VALUES - A data associated with specific ID under the KEY. Intended to represent a set of
/// values, hence the name.
///
/// Neither of ";:=" within KEY, ID and VALUES is allowed.
/// There should be none identical KEYs in the same db file.
/// There should be none identical IDs within the same record.
///
/// Intended usage:
/// KEY: A stringized problem config.
/// ID: A symbolic name of the Solver applicable for the KEY (problem config). There could be
/// several Solvers able to handle the same config, so several IDs can be put under a KEY.
/// Format of VALUES stored under each ID is Solver-specific. in other words, how a set of values
/// (or whatever a Solver wants to store in VALUES) is encoded into a string depends on the Solver.
/// Note: If VALUES is used to represent a set of numeric values, then it is recommended to use ","
/// as a separator.

/// Represents a db record associated with specific KEY.
/// Ctor arguments are path to db file and a KEY (or an object able to provide a KEY).
/// Upon construction, allows getting and modifying contents of a record (IDs and VALUES).
///
/// All operations are MP- and MT-safe.
class DbRecord
{
    public:
    template <class TValue>
    class Iterator
    {
        friend class DbRecord;

        using InnerIterator = std::unordered_map<std::string, std::string>::const_iterator;

        public:
        std::pair<const std::string&, TValue> operator*() const
        {
            assert(it != InnerIterator{});
            TValue value;
            value.Deserialize(it->second);
            return {it->first, value};
        }

        Iterator& operator++()
        {
            ++it;
            return *this;
        }

        const Iterator operator++(int) { return Iterator{it++}; }

        bool operator==(const Iterator& other) const { return it == other.it; }
        bool operator!=(const Iterator& other) const { return it != other.it; }

        private:
        Iterator(const InnerIterator it_) : it(it_) {}
        InnerIterator it;
    };

    template <class TValue>
    class IterationHelper
    {
        public:
        Iterator<TValue> begin() const { return {record.map.begin()}; }
        Iterator<TValue> end() const { return {record.map.end()}; }

        private:
        IterationHelper(const DbRecord& record_) : record(record_) {}

        const DbRecord& record;
        friend class DbRecord;
    };

    private:
    std::string key;
    std::unordered_map<std::string, std::string> map;

    template <class T>
    static // 'static' is for calling from ctor
        std::string
        Serialize(const T& data)
    {
        std::ostringstream ss;
        data.Serialize(ss);
        return ss.str();
    }

    bool ParseContents(const std::string& contents);
    void WriteContents(std::ostream& stream) const;
    bool SetValues(const std::string& id, const std::string& values);
    bool GetValues(const std::string& id, std::string& values) const;

    DbRecord(const std::string& key_) : key(key_) {}

    public:
    /// T shall provide a db KEY by means of the "void Serialize(std::ostream&) const" member
    /// function.
    template <class T>
    DbRecord(const T& problem_config_) : DbRecord(Serialize(problem_config_))
    {
    }

    /// Merges data from this record to data from that record if their keys are same.
    /// This record would contain all ID:VALUES pairs from that record that are not in this.
    /// E.g. this = {ID1:VALUE1}
    ///      that = {ID1:VALUE3, ID2:VALUE2}
    ///      this.Merge(that) = {ID1:VALUE1, ID2:VALUE2}
    void Merge(const DbRecord& that);

    /// Obtains VALUES from an object of class T and sets it in record (in association with ID,
    /// under the current KEY).
    /// T shall have the "void Serialize(std::ostream&) const" member function available.
    ///
    /// Returns true if records data was changed.
    template <class T>
    bool SetValues(const std::string& id, const T& values)
    {
        return SetValues(id, Serialize(values));
    }

    /// Get VALUES associated with ID under the current KEY and delivers those to a member function
    /// of a class T object. T shall have the "bool Deserialize(const std::string& str)"
    /// member function available.
    ///
    /// Returns false if there is none ID:VALUES in the record or in case of any error, e.g. if
    /// VALUES cannot be deserialized due to incorrect format.
    template <class T>
    bool GetValues(const std::string& id, T& values) const
    {
        std::string s;
        if(!GetValues(id, s))
            return false;

        const bool ok = values.Deserialize(s);
        if(!ok)
            MIOPEN_LOG((MIOPEN_INSTALLABLE ? LoggingLevel::Warning : miopen::LoggingLevel::Error),
                       "Perf db record is obsolete or corrupt: " << s
                                                                 << ". Performance may degrade.");
        return ok;
    }

    /// Removes ID with associated VALUES from this record.
    ///
    /// Returns true if erase was successful. Returns false if this ID was not found.
    bool EraseValues(const std::string& id);

    template <class TValue>
    IterationHelper<TValue> As() const
    {
        return *this;
    }

    friend class Db;
};

} // namespace miopen

#endif // GUARD_MIOPEN_DB_RECORD_HPP_
