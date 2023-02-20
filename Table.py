import mysql.connector
import os
import re
import datetime as dt
import requests
import errno
import shutil
import json
import random
import sys
import argparse
from pprint import pprint
import re
from googleapiclient.discovery import build
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

def read_config():
        return json.loads(config_file.read())

TableDic = { # Primary ключи таблиц
        }

def get_db_connection(config):
    return mysql.connector.connect(user=config['mysql']['user'], password=config['mysql']['pwd'],
                              host=config['mysql']['host'],
                              database=config['mysql']['db'])


class Table(object):
    def __init__(self, TableName):
        self.TableName = TableName
        if TableDic[TableName]:
            self.primary = TableDic[TableName]
        self.info = {}
        #self.getFieldInfo()
        self.config = read_config()
        self.getFieldDic()
    
    def getFieldDic(self):
        self.FieldDic = []
        cnx = AODDB.get_db_connection(self.config)
        cursor = cnx.cursor()
        query = f"SELECT COLUMN_NAME , DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = Database() AND TABLE_NAME = '{self.TableName}'";
        cursor = cnx.cursor()
        cursor.execute(query)
        res = []
        for (field) in cursor:
            res.append(field[0])
        cursor.close()
        cnx.close()
        self.FieldDic = res
    
    @property
    def exists(self):
        if ((self)and(self.info)and(TableDic[self.TableName] in self.info)and(self.info[TableDic[self.TableName]])):
            return True
        else:
            return False

    def field_value(self, field_name):
        if self.info:
            if not field_name in self.info.keys():
                return None
            if self.info[field_name]:
                return self.info[field_name]
        return None

    def getFieldInfo(self, PrimaryKey):
        self.info = {}
        if (PrimaryKey):
            pass
        else:
            return None
        cnx = AODDB.get_db_connection(self.config)
        cursor = cnx.cursor()
        fields = ", ".join(self.FieldDic)
        if self.primary: 
            query = f"select {fields} from `{self.TableName}` where {self.primary} = '{PrimaryKey}'"
        else:
            query = f"select {fields} from `{self.TableName}` where {TableDic[self.TableName]} = '{PrimaryKey}'"
        cursor = cnx.cursor()
        cursor.execute(query)
        res = {}
        temp = cursor.fetchone()
        if not temp:
            self.info = None
            cursor.close()
            cnx.close()
        else:
            for index, field in enumerate(self.FieldDic):
                res[field] = temp[index]
            self.info = res
            cursor.close()
            cnx.close()
        #return res

    def update(self, new_content, forceInsert = False):
        if not self.primary:
            return None
        if not self.TableName:
            return None
        if (not self.info)and(forceInsert):
            res = AODDB.insert_single(self.TableName, new_content)
            self.getFieldInfo(res)
            return None
        if (not self.info):
            return None
        not_equal = 0
        for key in new_content.keys():
            if str(new_content[key]).lower() != str(self.info[key]).lower():
                not_equal = 1
        if not_equal == 0:
            return None
        res = AODDB.update_single(self.TableName, new_content, self.primary, self.info[self.primary])
        if not res:
            self.getFieldInfo(self.info[self.primary])
        return res

import AODDB













