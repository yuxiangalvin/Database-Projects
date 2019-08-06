#include <assert.h>
#include <stdlib.h>
#include <math.h>
#include <vector>

#include "btree.h"

KeyValuePair::KeyValuePair()
{
}

KeyValuePair::KeyValuePair(const KEY_T &k, const VALUE_T &v) : key(k), value(v)
{
}

KeyValuePair::KeyValuePair(const KeyValuePair &rhs) : key(rhs.key), value(rhs.value)
{
}

KeyValuePair::~KeyValuePair()
{
}

KeyValuePair &KeyValuePair::operator=(const KeyValuePair &rhs)
{
  return *(new (this) KeyValuePair(rhs));
}

BTreeIndex::BTreeIndex(SIZE_T keysize,
                       SIZE_T valuesize,
                       BufferCache *cache,
                       bool unique)
{
  superblock.info.keysize = keysize;
  superblock.info.valuesize = valuesize;
  buffercache = cache;
  // note: ignoring unique now
}

BTreeIndex::BTreeIndex()
{
  // shouldn't have to do anything
}

//
// Note, will not attach!
//
BTreeIndex::BTreeIndex(const BTreeIndex &rhs)
{
  buffercache = rhs.buffercache;
  superblock_index = rhs.superblock_index;
  superblock = rhs.superblock;
}

BTreeIndex::~BTreeIndex()
{
  // shouldn't have to do anything
}

BTreeIndex &BTreeIndex::operator=(const BTreeIndex &rhs)
{
  return *(new (this) BTreeIndex(rhs));
}

ERROR_T BTreeIndex::AllocateNode(SIZE_T &n)
{
  n = superblock.info.freelist;

  if (n == 0)
  {
    return ERROR_NOSPACE;
  }

  BTreeNode node;

  node.Unserialize(buffercache, n);

  assert(node.info.nodetype == BTREE_UNALLOCATED_BLOCK);

  superblock.info.freelist = node.info.freelist;

  superblock.Serialize(buffercache, superblock_index);

  buffercache->NotifyAllocateBlock(n);

  return ERROR_NOERROR;
}

ERROR_T BTreeIndex::DeallocateNode(const SIZE_T &n)
{
  BTreeNode node;

  node.Unserialize(buffercache, n);

  assert(node.info.nodetype != BTREE_UNALLOCATED_BLOCK);

  node.info.nodetype = BTREE_UNALLOCATED_BLOCK;

  node.info.freelist = superblock.info.freelist;

  node.Serialize(buffercache, n);

  superblock.info.freelist = n;

  superblock.Serialize(buffercache, superblock_index);

  buffercache->NotifyDeallocateBlock(n);

  return ERROR_NOERROR;
}

ERROR_T BTreeIndex::Attach(const SIZE_T initblock, const bool create)
{
  ERROR_T rc;

  superblock_index = initblock;
  assert(superblock_index == 0);

  if (create)
  {
    // build a super block, root node, and a free space list
    //
    // Superblock at superblock_index
    // root node at superblock_index+1
    // free space list for rest
    BTreeNode newsuperblock(BTREE_SUPERBLOCK,
                            superblock.info.keysize,
                            superblock.info.valuesize,
                            buffercache->GetBlockSize());
    newsuperblock.info.rootnode = superblock_index + 1;
    newsuperblock.info.freelist = superblock_index + 2;
    newsuperblock.info.numkeys = 0;

    buffercache->NotifyAllocateBlock(superblock_index);

    rc = newsuperblock.Serialize(buffercache, superblock_index);

    if (rc)
    {
      return rc;
    }

    BTreeNode newrootnode(BTREE_ROOT_NODE,
                          superblock.info.keysize,
                          superblock.info.valuesize,
                          buffercache->GetBlockSize());
    newrootnode.info.rootnode = superblock_index + 1;
    newrootnode.info.freelist = superblock_index + 2;
    newrootnode.info.numkeys = 0;

    buffercache->NotifyAllocateBlock(superblock_index + 1);

    rc = newrootnode.Serialize(buffercache, superblock_index + 1);

    if (rc)
    {
      return rc;
    }

    for (SIZE_T i = superblock_index + 2; i < buffercache->GetNumBlocks(); i++)
    {
      BTreeNode newfreenode(BTREE_UNALLOCATED_BLOCK,
                            superblock.info.keysize,
                            superblock.info.valuesize,
                            buffercache->GetBlockSize());
      newfreenode.info.rootnode = superblock_index + 1;
      newfreenode.info.freelist = ((i + 1) == buffercache->GetNumBlocks()) ? 0 : i + 1;

      rc = newfreenode.Serialize(buffercache, i);

      if (rc)
      {
        return rc;
      }
    }
  }

  // OK, now, mounting the btree is simply a matter of reading the superblock

  return superblock.Unserialize(buffercache, initblock);
}

ERROR_T BTreeIndex::Detach(SIZE_T &initblock)
{
  return superblock.Serialize(buffercache, superblock_index);
}


ERROR_T BTreeIndex::LookupOrUpdateInternal(const SIZE_T &node,
                                           const BTreeOp op,
                                           const KEY_T &key,
                                           VALUE_T &value)
{
  BTreeNode b;
  ERROR_T rc;
  SIZE_T offset;
  KEY_T testkey;
  SIZE_T ptr;

  rc = b.Unserialize(buffercache, node);

  if (rc != ERROR_NOERROR){
    return rc;
  }

  switch (b.info.nodetype)
  {
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:
    // Scan through key/ptr pairs
    //and recurse if possible
    for (offset = 0; offset < b.info.numkeys; offset++)
    {
      rc = b.GetKey(offset, testkey);
      if (rc) {return rc;}
      if (key < testkey || key == testkey)
      {
        // OK, so we now have the first key that's larger
        // so we ned to recurse on the ptr immediately previous to
        // this one, if it exists
        rc = b.GetPtr(offset, ptr);
        if (rc)
        {return rc;}
        return LookupOrUpdateInternal(ptr, op, key, value);
      }
    }
    // if we got here, we need to go to the next pointer, if it exists
    if (b.info.numkeys > 0)
    {
      rc = b.GetPtr(b.info.numkeys, ptr);
      if (rc)
      {
        return rc;
      }
      return LookupOrUpdateInternal(ptr, op, key, value);
    }
    else
    {
      // There are no keys at all on this node, so nowhere to go
      return ERROR_NONEXISTENT;
    }
    break;
  case BTREE_LEAF_NODE:
    // Scan through keys looking for matching value
    for (offset = 0; offset < b.info.numkeys; offset++)
    {
      rc = b.GetKey(offset, testkey);
      if (rc)
      {
        return rc;
      }
      if (testkey == key)
      {
        if (op == BTREE_OP_LOOKUP)
        {
          return b.GetVal(offset, value);
        }
        else
        {
          ERROR_T set_val_rc = b.SetVal(offset, value);
          if (set_val_rc != ERROR_NOERROR)
          {
            return set_val_rc;
          }

          ERROR_T serialize_rc = b.Serialize(buffercache, node);
          if (serialize_rc != ERROR_NOERROR)
          {
            return serialize_rc;
          }
          return ERROR_NOERROR;
        }
      }
    }
    return ERROR_NONEXISTENT;
    break;
  default:
    // We can't be looking at anything other than a root, internal, or leaf
    return ERROR_INSANE;
    break;
  }

  return ERROR_INSANE;
}

static ERROR_T PrintNode(ostream &os, SIZE_T nodenum, BTreeNode &b, BTreeDisplayType dt)
{
  KEY_T key;
  VALUE_T value;
  SIZE_T ptr;
  SIZE_T offset;
  ERROR_T rc;
  unsigned i;

  if (dt == BTREE_DEPTH_DOT)
  {
    os << nodenum << " [ label=\"" << nodenum << ": ";
  }
  else if (dt == BTREE_DEPTH)
  {
    os << nodenum << ": ";
  }
  else
  {
  }

  switch (b.info.nodetype)
  {
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:
    if (dt == BTREE_SORTED_KEYVAL)
    {
    }
    else
    {
      if (dt == BTREE_DEPTH_DOT)
      {
      }
      else
      {
        os << "Interior: ";
      }
      for (offset = 0; offset <= b.info.numkeys; offset++)
      {
        rc = b.GetPtr(offset, ptr);
        if (rc)
        {
          return rc;
        }
        os << "*" << ptr << " ";
        // Last pointer
        if (offset == b.info.numkeys)
          break;
        rc = b.GetKey(offset, key);
        if (rc)
        {
          return rc;
        }
        for (i = 0; i < b.info.keysize; i++)
        {
          os << key.data[i];
        }
        os << " ";
      }
    }
    break;
  case BTREE_LEAF_NODE:
    if (dt == BTREE_DEPTH_DOT || dt == BTREE_SORTED_KEYVAL)
    {
    }
    else
    {
      os << "Leaf: ";
    }
    for (offset = 0; offset < b.info.numkeys; offset++)
    {
      if (offset == 0)
      {
        // special case for first pointer
        rc = b.GetPtr(offset, ptr);
        if (rc)
        {
          return rc;
        }
        if (dt != BTREE_SORTED_KEYVAL)
        {
          os << "*" << ptr << " ";
        }
      }
      if (dt == BTREE_SORTED_KEYVAL)
      {
        os << "(";
      }
      rc = b.GetKey(offset, key);
      if (rc)
      {
        return rc;
      }
      for (i = 0; i < b.info.keysize; i++)
      {
        os << key.data[i];
      }
      if (dt == BTREE_SORTED_KEYVAL)
      {
        os << ",";
      }
      else
      {
        os << " ";
      }
      rc = b.GetVal(offset, value);
      if (rc)
      {
        return rc;
      }
      for (i = 0; i < b.info.valuesize; i++)
      {
        os << value.data[i];
      }
      if (dt == BTREE_SORTED_KEYVAL)
      {
        os << ")\n";
      }
      else
      {
        os << " ";
      }
    }
    break;
  default:
    if (dt == BTREE_DEPTH_DOT)
    {
      os << "Unknown(" << b.info.nodetype << ")";
    }
    else
    {
      os << "Unsupported Node Type " << b.info.nodetype;
    }
  }
  if (dt == BTREE_DEPTH_DOT)
  {
    os << "\" ]";
  }
  return ERROR_NOERROR;
}

ERROR_T BTreeIndex::Lookup(const KEY_T &key, VALUE_T &value)
{
  return LookupOrUpdateInternal(superblock.info.rootnode, BTREE_OP_LOOKUP, key, value);
}

ERROR_T BTreeIndex::Insert(const KEY_T &key, const VALUE_T &value)
{
  VALUE_T valueparam = value;
  SIZE_T adjusted_block;
  KEY_T adjusted_key; 
  return InsertAfterAdjust(superblock.info.rootnode, key, valueparam, adjusted_block,adjusted_key);
}


ERROR_T BTreeIndex::InsertAfterAdjust(const SIZE_T &start_ptr, const KEY_T &key, const VALUE_T &value, SIZE_T &adjusted_block, KEY_T &adjusted_key)
{
    BTreeNode b;
    ERROR_T rc;
    SIZE_T offset;
    KEY_T test_key;
    SIZE_T ptr;
    KEY_T last_leaf_key;

    rc= b.Unserialize(buffercache,start_ptr);

    if (rc!=ERROR_NOERROR) { 
      return rc;
    }
    
    switch (b.info.nodetype) { 
      case BTREE_ROOT_NODE:

    if (b.info.numkeys == 0)
    { 
      SIZE_T leftLeafBlock;
      SIZE_T rightLeafBlock;
      BTreeNode leftLeaf(BTREE_LEAF_NODE, superblock.info.keysize, superblock.info.valuesize, superblock.info.blocksize);
      BTreeNode rightLeaf(BTREE_LEAF_NODE, superblock.info.keysize, superblock.info.valuesize, superblock.info.blocksize);
      rc = AllocateNode(leftLeafBlock);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      rc = AllocateNode(rightLeafBlock);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }

      b.info.numkeys++;
      b.SetKey(0, key);
      b.SetPtr(0, leftLeafBlock);
      b.SetPtr(1, rightLeafBlock);

      leftLeaf.info.numkeys++;
      leftLeaf.SetKey(0, key);
      leftLeaf.SetVal(0, value);

      rc = b.Serialize(buffercache, start_ptr);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      rc = leftLeaf.Serialize(buffercache, leftLeafBlock);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      rc = rightLeaf.Serialize(buffercache, rightLeafBlock);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      return ERROR_NOERROR;
    }
    else
    {
    }
      
case BTREE_INTERIOR_NODE:

    for (offset = 0; offset < b.info.numkeys; offset++)
    {
      rc = b.GetKey(offset, test_key);
      if (rc)
      {
        return rc;
      }
      if (key < test_key || key == test_key)
      {
        if (key == test_key)
        {
          return ERROR_UNIQUE_KEY;
        }
        rc = b.GetPtr(offset, ptr);
        if (rc)
        {
          return rc;
        }
        ERROR_T insert_recur_error;
        insert_recur_error = InsertAfterAdjust(ptr, key, value, adjusted_block, adjusted_key);

        if (insert_recur_error == ERROR_SPLIT_BLOCK)
        { 
          SIZE_T old_num_keys = b.info.numkeys;
          b.info.numkeys++;

          SIZE_T last_ptr;
          rc = b.GetPtr(old_num_keys, last_ptr);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }
          rc = b.SetPtr(old_num_keys + 1, last_ptr);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }

          for (SIZE_T i = old_num_keys - 1; (i >= offset); i--)
          {
            KEY_T shifted_key;
            rc = b.GetKey(i, shifted_key);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = b.SetKey(i + 1, shifted_key);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            SIZE_T shifted_ptr;
            rc = b.GetPtr(i, shifted_ptr);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = b.SetPtr(i + 1, shifted_ptr);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            if(i==0){
                break;
            }
          }

          rc = b.SetKey(offset, adjusted_key);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }
          rc = b.SetPtr(offset, adjusted_block);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }

        }
        else
        {
          return insert_recur_error;
        }

      interior_node_split:

        if ((b.info.numkeys - b.info.GetNumSlotsAsInterior()) <= 1)
        { 
          BTreeNode new_block(BTREE_INTERIOR_NODE, superblock.info.keysize, superblock.info.valuesize, superblock.info.blocksize);

          rc = AllocateNode(adjusted_block);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }

          SIZE_T old_b_num = b.info.numkeys;
          SIZE_T last_ptr;
          rc = b.GetPtr(old_b_num, last_ptr);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }

          SIZE_T num_shifted = 0;
          for (SIZE_T i = (b.info.numkeys / 2) + 1; i < old_b_num; i++)
          {
            new_block.info.numkeys++;
            KEY_T shifted_key;
            rc = b.GetKey(i, shifted_key);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = new_block.SetKey(num_shifted, shifted_key);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            SIZE_T shifted_ptr;
            rc = b.GetPtr(i, shifted_ptr);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = new_block.SetPtr(num_shifted, shifted_ptr);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            num_shifted++;
          }

          b.info.numkeys -= num_shifted;

          rc = new_block.SetPtr(num_shifted, last_ptr);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }
          rc = b.GetKey(b.info.numkeys - 1, adjusted_key);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }
          b.info.numkeys--;

          rc = new_block.Serialize(buffercache, start_ptr);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }
          rc = b.Serialize(buffercache, adjusted_block);
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }

          if (b.info.nodetype == BTREE_ROOT_NODE)
          { 
            b.info.nodetype = BTREE_INTERIOR_NODE;
            BTreeNode new_root(BTREE_ROOT_NODE, superblock.info.keysize, superblock.info.valuesize, superblock.info.blocksize);
            SIZE_T new_root_block;
            new_root.info.numkeys++;
            rc = new_root.SetKey(0, adjusted_key);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = new_root.SetPtr(0, adjusted_block);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = new_root.SetPtr(1, start_ptr);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            rc = AllocateNode(new_root_block);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            rc = b.Serialize(buffercache, adjusted_block);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            rc = new_root.Serialize(buffercache, new_root_block);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            superblock.info.rootnode = new_root_block;

            rc = superblock.Serialize(buffercache, superblock_index);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }

            return ERROR_NOERROR;
          }
          else
          {
            return ERROR_SPLIT_BLOCK;
          }
        }
        else
        {
          return b.Serialize(buffercache, start_ptr);
        }
      }
    }
    if (b.info.numkeys > 0)
    {

      rc = b.GetPtr(b.info.numkeys, ptr);
      if (rc)
      {
        return rc;
      }

      ERROR_T insert_error = InsertAfterAdjust(ptr, key, value, adjusted_block, adjusted_key);

      if (insert_error == ERROR_SPLIT_BLOCK)
      {
        SIZE_T last_ptr;
        SIZE_T old_num_keys = b.info.numkeys;
        b.info.numkeys++;
        rc = b.GetPtr(old_num_keys, last_ptr);
        if (rc != ERROR_NOERROR)
        {
          return rc;
        }
        rc = b.SetPtr(old_num_keys + 1, last_ptr);
        if (rc != ERROR_NOERROR)
        {
          return rc;
        }

        rc = b.SetKey(old_num_keys, adjusted_key);
        if (rc != ERROR_NOERROR)
        {
          return rc;
        }
        rc = b.SetPtr(old_num_keys, adjusted_block);
        if (rc != ERROR_NOERROR)
        {
          return rc;
        }

        goto interior_node_split;
      }
      else if (insert_error == ERROR_UNIQUE_KEY)
      {
        return insert_error;
      }
      else
      {
        return b.Serialize(buffercache, start_ptr);
      }
    }
    else
    {
      return ERROR_NONEXISTENT;
    }
    break;

      case BTREE_LEAF_NODE:

    if (b.info.numkeys == 0)
    {
      b.info.numkeys++;
      rc = b.SetKey(0, key);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      rc = b.SetVal(0, value);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      return b.Serialize(buffercache, start_ptr);
    }

    b.GetKey((b.info.numkeys - 1), last_leaf_key);

    if (!(last_leaf_key < key))
    {
      for (offset = 0; offset < b.info.numkeys; offset++)
      {
        rc = b.GetKey(offset, test_key);
        if (rc)
        {
          return rc;
        }
        if (key < test_key || key == test_key)
        {
          if (key == test_key)
          {
            return ERROR_UNIQUE_KEY;
          }

          SIZE_T old_num_keys = b.info.numkeys;
          b.info.numkeys++;

          for (SIZE_T i = old_num_keys - 1; i >= offset; i--)
          {
            KeyValuePair kvp;
            rc = b.GetKeyVal(i, kvp);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            rc = b.SetKeyVal(i + 1, kvp);
            if (rc != ERROR_NOERROR)
            {
              return rc;
            }
            if (i == 0)
            {
              break;
            }
          }

          rc = b.SetKeyVal(offset, KeyValuePair(key, value));
          if (rc != ERROR_NOERROR)
          {
            return rc;
          }

          break;
        }
      }
    }
    else
    {
      b.info.numkeys++;
      rc = b.SetKey(b.info.numkeys - 1, key);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      rc = b.SetVal(b.info.numkeys - 1, value);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
    }

    if ((b.info.numkeys - b.info.GetNumSlotsAsLeaf()) > 1)
    {
      return b.Serialize(buffercache, start_ptr);
    }
    else
    {
      BTreeNode newNode(BTREE_LEAF_NODE, superblock.info.keysize, superblock.info.valuesize, superblock.info.blocksize);

      rc = AllocateNode(adjusted_block);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }

      KeyValuePair kvp;
      SIZE_T j = 0;

      SIZE_T old_num_keys2 = b.info.numkeys;
      for (SIZE_T i = b.info.numkeys / 2; i < old_num_keys2; i++)
      {
        rc = b.GetKeyVal(i, kvp);
        if (rc != ERROR_NOERROR)
        {
          return rc;
        }
        newNode.info.numkeys++;
        rc = newNode.SetKeyVal(j, kvp);
        if (rc != ERROR_NOERROR)
        {
          return rc;
        }
        j++;
      }
      b.info.numkeys -= j;

      rc = b.GetKey(b.info.numkeys - 1, adjusted_key);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }

      rc = newNode.Serialize(buffercache, start_ptr);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }
      rc = b.Serialize(buffercache, adjusted_block);
      if (rc != ERROR_NOERROR)
      {
        return rc;
      }

      return ERROR_SPLIT_BLOCK;
    }

    break;

  default:
    return ERROR_INSANE;
    break;
  }
  return ERROR_INSANE;
}




ERROR_T BTreeIndex::Update(const KEY_T &key, const VALUE_T &value)
{
  VALUE_T update_value = value;
  return LookupOrUpdateInternal(superblock.info.rootnode, BTREE_OP_UPDATE, key, update_value);
}

ERROR_T BTreeIndex::Delete(const KEY_T &key)
{
  return DeleteRecursion(superblock.info.rootnode, key);
}

ERROR_T BTreeIndex::DeleteRecursion(const SIZE_T &start_ptr, const KEY_T &key)    
{    
    BTreeNode b;
    ERROR_T rc;
    SIZE_T offset;
    KEY_T test_key;
    SIZE_T ptr;

    rc= b.Unserialize(buffercache,start_ptr);

    if (rc!=ERROR_NOERROR)
    { 
      return rc;
    }

  switch (b.info.nodetype)
  { 
    case BTREE_ROOT_NODE:
        break;

    case BTREE_INTERIOR_NODE:
        for (offset=0; offset<b.info.numkeys; offset++)
        { 
            rc=b.GetKey(offset, test_key);
            if (rc) 
            {
              return rc;
            }
            if (key < test_key)
            {
            rc=b.GetPtr(offset, ptr);
              if (rc)
              {
                return rc;
              }
            return DeleteRecursion(ptr, key);
            }
        }
        return ERROR_NONEXISTENT;
        break;
    
    case BTREE_LEAF_NODE:
      for (offset = 0; offset < b.info.numkeys; offset++)
      { 
        rc=b.GetKey(offset, test_key);
        if (rc)
        {
          return rc;
        }
        if (key == test_key)
        { 
          if(b.info.numkeys > 1)
          {
            b.info.numkeys--;
            if(offset == b.info.numkeys - 1)
            {
              superblock.info.freelist = start_ptr;
            }
            else
            {
              for(SIZE_T i = offset; i < (b.info.numkeys - 1); i++){
                  KEY_T shift_key;
                  b.GetKey(i, shift_key);
                  b.SetKey(i + 1, shift_key);

                  VALUE_T shift_value;
                  b.GetVal(i, shift_value);
                  b.SetVal(i + 1, shift_value);
              }
            }
            return b.Serialize(buffercache, start_ptr);
          }
          else
          {
            rc = DeallocateNode(start_ptr);
            if (rc)
            {
              return rc;
            } 
            else
            {
              return b.Serialize(buffercache, start_ptr);   
            }          
          } 
        }
      } 
      return ERROR_NONEXISTENT;
      break;

    default:
      return ERROR_INSANE;
  }
  return ERROR_NOERROR;
}

ERROR_T BTreeIndex::DisplayInternal(const SIZE_T &node,
                                    ostream &o,
                                    BTreeDisplayType display_type) const
{
  KEY_T testkey;
  SIZE_T ptr;
  BTreeNode b;
  ERROR_T rc;
  SIZE_T offset;

  rc = b.Unserialize(buffercache, node);

  if (rc != ERROR_NOERROR)
  {
    return rc;
  }

  rc = PrintNode(o, node, b, display_type);

  if (rc)
  {
    return rc;
  }

  if (display_type == BTREE_DEPTH_DOT)
  {
    o << ";";
  }

  if (display_type != BTREE_SORTED_KEYVAL)
  {
    o << endl;
  }

  switch (b.info.nodetype)
  {
  case BTREE_ROOT_NODE:
  case BTREE_INTERIOR_NODE:
    if (b.info.numkeys > 0)
    {
      for (offset = 0; offset <= b.info.numkeys; offset++)
      {
        rc = b.GetPtr(offset, ptr);
        if (rc)
        {
          return rc;
        }
        if (display_type == BTREE_DEPTH_DOT)
        {
          o << node << " -> " << ptr << ";\n";
        }
        rc = DisplayInternal(ptr, o, display_type);
        if (rc)
        {
          return rc;
        }
      }
    }
    return ERROR_NOERROR;
    break;
  case BTREE_LEAF_NODE:
    return ERROR_NOERROR;
    break;
  default:
    if (display_type == BTREE_DEPTH_DOT)
    {
    }
    else
    {
      o << "Unsupported Node Type " << b.info.nodetype;
    }
    return ERROR_INSANE;
  }

  return ERROR_NOERROR;
}

ERROR_T BTreeIndex::Display(ostream &o, BTreeDisplayType display_type) const
{
  ERROR_T rc;
  if (display_type == BTREE_DEPTH_DOT)
  {
    o << "digraph tree { \n";
  }
  rc = DisplayInternal(superblock.info.rootnode, o, display_type);
  if (display_type == BTREE_DEPTH_DOT)
  {
    o << "}\n";
  }
  return ERROR_NOERROR;
}

ERROR_T BTreeIndex::SanityCheck() const
{
  return ERROR_UNIMPL;
}

ostream &BTreeIndex::Print(ostream &os) const
{
  return os;
}